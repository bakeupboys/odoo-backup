#!/bin/bash
set -e

TARGET_DIR=$(pwd)

# Check for config
CONFIG_FILE="$TARGET_DIR/.env.backup"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file .env.backup not found in $TARGET_DIR"
    exit 1
fi

set -a
source "$CONFIG_FILE"   # export vars so restic child process sees them
set +a

# Usage: ./restore.sh [snapshot-id]
SNAPSHOT_ID="${1:-latest}"

TEMP_DIR=$(mktemp -d)

CONFIG_FILE="$TARGET_DIR/.env.backup"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file .env.backup not found in $TARGET_DIR"
    exit 1
fi

# 2. Dynamic Discovery
# --------------------
# Project/DB name derived from directory name, overridable via COMPOSE_DB_NAME.
# On a native install the convention is the same — just no Docker involved.
PROJECT_NAME=${PROJECT_NAME:-"production"}
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
DB_NAME=${COMPOSE_DB_NAME:-$PROJECT_NAME}
DB_NAME="staging-$DB_NAME"

# Odoo filestore location.
# Default: /var/lib/odoo/.local/share/Odoo/filestore/<db>
# Override in .env.backup with ODOO_FILESTORE_DIR if your install differs.
ODOO_FILESTORE_DIR="/var/lib/odoo/.local/share/Odoo/filestore/$DB_NAME"

if [ ! -d "$ODOO_FILESTORE_DIR" ]; then
    echo "Error: Filestore directory not found: $ODOO_FILESTORE_DIR"
    echo "Set ODOO_FILESTORE_DIR in .env.backup to override."
    exit 1
fi


# Check if snapshot exists before proceeding
if ! restic snapshots "$SNAPSHOT_ID" --json | grep -q '"id"'; then
  echo "Error: Snapshot $SNAPSHOT_ID not found in repository."
  exit 1
fi


# Stop staging instance restore
echo "Stopping stage instance"
sudo systemctl stop "odona-$DB_NAME"

# Mount repo to temp dir
echo "Restoring snapshot $SNAPSHOT_ID to $TEMP_DIR ..."
restic mount "$TEMP_DIR" &

# Wait until mount is ready
echo "Waiting for mount..."
until mountpoint -q "$TEMP_DIR"; do
    sleep 0.5
done
echo "Mount ready"

cleanup() {
    echo "Unmounting $TEMP_DIR ..."
    fusermount -u "$TEMP_DIR"
    wait $RESTIC_PID 2>/dev/null
}
trap cleanup EXIT

echo "Restoring database from dump..."
# Restore database from dump
RESTORE_PATH="$TEMP_DIR/snapshots/$SNAPSHOT_ID"
RESTORE_DB_FILE="$RESTORE_PATH/odoo_db.dump"
ls $RESTORE_PATH
echo $RESTORE_DB_FILE
if [ -f $RESTORE_DB_FILE ]; then
  dropdb -U odoo "$DB_NAME"
  createdb -U odoo "$DB_NAME"
  pg_restore -U odoo -d "$DB_NAME" < $RESTORE_DB_FILE
  # Neutralize database
  odoo neutralize -c "/etc/odona/$DB_NAME/odoo.conf" --no-http --stop-after-init
else
  echo "Database dump not found in backup. Skipping database restore."
fi

# Restart staging instance
sudo systemctl start "odona-$DB_NAME"

# Restore filestore
echo "Restoring filestore ..."

echo "rsync -av --checksum --delete --exclude='odoo_db.dump' $RESTORE_PATH $ODOO_FILESTORE_DIR"

echo "Cleaning up..."


# TODO: restart odona stage
echo "Stage complete for $DB_NAME!"
