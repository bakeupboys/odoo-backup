#!/bin/bash
set -e

# Usage: ./backup.sh /path/to/odoo/instance
TARGET_DIR="$1"

# 1. Validation & Setup
# ---------------------
if [ -z "$TARGET_DIR" ]; then
    echo "Error: No target directory provided."
    echo "Usage: $0 /path/to/odoo/instance"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

# Convert to absolute path
cd "$TARGET_DIR"
TARGET_DIR=$(pwd)

# Check for config
CONFIG_FILE="$TARGET_DIR/.env.backup"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file .env.backup not found in $TARGET_DIR"
    exit 1
fi

# 2. Dynamic Discovery
# --------------------
# We derive the project name from the directory name (Docker Compose default)
# Or you can override it in .env.backup with COMPOSE_PROJECT_NAME
PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename "$TARGET_DIR")}
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')

# Dynamically find the running DB container ID
# We assume the service name in docker-compose is 'db'. Change if yours is different.
DB_CONTAINER_ID=$(docker compose ps -q db)

if [ -z "$DB_CONTAINER_ID" ]; then
    echo "Error: Could not find a running container for service 'db'."
    echo "Ensure docker-compose is up."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_TEMP_DIR="$TARGET_DIR/backups_temp"

echo "=========================================="
echo "Starting Backup for: $PROJECT_NAME"
echo "Directory: $TARGET_DIR"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="

# 3. Preparation
# ----------------
mkdir -p "$BACKUP_TEMP_DIR"

# 4. Database Dump
# ----------------
echo ">>> Dumping Database from container $DB_CONTAINER_ID..."
docker exec "$DB_CONTAINER_ID" pg_dump -U odoo -d postgres -Fc > "$BACKUP_TEMP_DIR/odoo_db.dump"

# 5. Restic Backup
# ----------------
echo ">>> Pushing to Remote via Restic..."

# Note: We use the discovered PROJECT_NAME to find the volumes
docker run --rm \
  --env-file "$CONFIG_FILE" \
  -v "$HOME/.ssh:/ssh:ro" \
  -v "$BACKUP_TEMP_DIR:/backup/db" \
  -v "${PROJECT_NAME}_odoo-data:/backup/filestore:ro" \
  -v "${PROJECT_NAME}_db-data:/backup/raw_db_files:ro" \
  -v "${PROJECT_NAME}_config:/backup/config:ro" \
  --entrypoint sh \
  restic/restic \
  -c "cp /ssh/* ~/.ssh/ && restic backup /backup --tag \"daily-backup\" --tag \"$PROJECT_NAME\" --host \"$PROJECT_NAME\""

# 6. Pruning
# ----------------
echo ">>> Pruning old backups..."
docker run --rm \
  --env-file "$CONFIG_FILE" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  --entrypoint sh \
  restic/restic \
  -c "cp /ssh/* ~/.ssh/ && restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune"

# 7. Cleanup
# ----------------
rm -rf "$BACKUP_TEMP_DIR"
echo ">>> Backup Complete for $PROJECT_NAME!"
echo ""
