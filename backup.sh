#!/bin/bash
set -e

TARGET_DIR=$(pwd)

# Check for config
CONFIG_FILE="$TARGET_DIR/.env.backup"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file .env.backup not found in $TARGET_DIR"
    exit 1
fi

source "$CONFIG_FILE"

# 2. Dynamic Discovery
# --------------------
# Project/DB name derived from directory name, overridable via COMPOSE_DB_NAME.
# On a native install the convention is the same — just no Docker involved.
PROJECT_NAME=${PROJECT_NAME:-"production"}
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
DB_NAME=${COMPOSE_DB_NAME:-$PROJECT_NAME}

# Odoo filestore location.
# Default: /var/lib/odoo/.local/share/Odoo/filestore/<db>
# Override in .env.backup with ODOO_FILESTORE_DIR if your install differs.
ODOO_FILESTORE_DIR=${ODOO_FILESTORE_DIR:-"/var/lib/odoo/.local/share/Odoo/filestore/$DB_NAME"}

if [ ! -d "$ODOO_FILESTORE_DIR" ]; then
    echo "Error: Filestore directory not found: $ODOO_FILESTORE_DIR"
    echo "Set ODOO_FILESTORE_DIR in .env.backup to override."
    exit 1
fi

# PostgreSQL connection settings — override in .env.backup as needed.
PG_USER=${PG_USER:-odoo}
PG_HOST=${PG_HOST:-localhost}
PG_PORT=${PG_PORT:-5432}

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_TEMP_DIR="$TARGET_DIR/backups_temp"

echo "=========================================="
echo "Starting Backup for: $PROJECT_NAME"
echo "DB Name:             $DB_NAME"
echo "Directory:           $TARGET_DIR"
echo "Filestore:           $ODOO_FILESTORE_DIR"
echo "Timestamp:           $TIMESTAMP"
echo "=========================================="

# 3. Preparation
# ----------------
mkdir -p "$BACKUP_TEMP_DIR"

# 4. Database Dump
# ----------------
echo ">>> Dumping Database..."
# pg_dump connects directly to the local PostgreSQL instance.
# If the OS user running this script is not a PostgreSQL superuser, make sure
# it has at minimum SELECT privileges on the target database, or run the script
# as the 'postgres' / 'odoo' OS user, or configure a ~/.pgpass file so that
# no interactive password prompt is needed.
#PGHOST="$PG_HOST" PGPORT="$PG_PORT" \
# pg_dump -U "$PG_USER" -d "$DB_NAME" -Fc \
pg_dump -d "$DB_NAME" -Fc \
    > "$ODOO_FILESTORE_DIR/odoo_db.dump"

# 5. Restic Backup
# ----------------
echo ">>> Pushing to Remote via Restic..."
# restic must be installed on the host: https://restic.readthedocs.io/
# All RESTIC_* and destination variables are read from .env.backup.
# SSH keys are picked up from the running user's ~/.ssh as before.
set -a
source "$CONFIG_FILE"   # export vars so restic child process sees them
set +a

cd $ODOO_FILESTORE_DIR

restic backup \
    . \
    --tag "daily-backup" \
    --tag "$PROJECT_NAME" \
    --host "$PROJECT_NAME"

# 6. Pruning
# ----------------
echo ">>> Pruning old backups..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

# 7. Cleanup
# ----------------
rm "$ODOO_FILESTORE_DIR/odoo_db.dump"

echo ">>> Backup Complete for $PROJECT_NAME!"
echo ""
