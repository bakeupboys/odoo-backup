#!/bin/bash
set -e

# Usage: ./restore.sh /path/to/odoo/instance <snapshot-id>
TARGET_DIR="$1"
SNAPSHOT_ID="$2"

if [ -z "$TARGET_DIR" ] || [ -z "$SNAPSHOT_ID" ]; then
    echo "Usage: $0 /path/to/odoo/instance <snapshot-id>"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

cd "$TARGET_DIR"
TARGET_DIR=$(pwd)

CONFIG_FILE="$TARGET_DIR/.env.backup"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file .env.backup not found in $TARGET_DIR"
    exit 1
fi

# Derive project name as in backup.sh
PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename "$TARGET_DIR")}
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')

# Find running DB container
DB_CONTAINER_ID=$(docker compose ps -q db)
if [ -z "$DB_CONTAINER_ID" ]; then
    echo "Error: Could not find a running container for service 'db'."
    echo "Ensure docker-compose is up."
    exit 1
fi

RESTORE_TEMP_DIR="$TARGET_DIR/restore_temp"
mkdir -p "$RESTORE_TEMP_DIR"

echo "Restoring snapshot $SNAPSHOT_ID to $RESTORE_TEMP_DIR ..."

# Check if snapshot exists before proceeding
if ! docker run --rm \
  --env-file "$CONFIG_FILE" \
  -v "$HOME/.ssh:/ssh:ro" \
  --entrypoint sh \
  restic/restic \
  -c "mkdir -p ~/.ssh && cp /ssh/* ~/.ssh/ && restic snapshots $SNAPSHOT_ID --json | grep -q 'id'"; then
  echo "Error: Snapshot $SNAPSHOT_ID not found in repository."
  exit 1
fi

# 1. Restore snapshot to temp dir
docker run --rm \
  --env-file "$CONFIG_FILE" \
  -v "$HOME/.ssh:/ssh:ro" \
  -v "$RESTORE_TEMP_DIR:/restore" \
  --entrypoint sh \
  restic/restic \
  -c "mkdir -p ~/.ssh && cp /ssh/* ~/.ssh/ && restic restore $SNAPSHOT_ID --target /restore"

echo "Restoring filestore ..."
# 2. Restore filestore and config to Docker volumes
docker run --rm \
  -v "${PROJECT_NAME}_odoo-data:/data/filestore" \
  -v "$RESTORE_TEMP_DIR/backup/filestore:/from_backup:ro" \
  alpine \
  sh -c "rm -rf /data/filestore/* && cp -a /from_backup/. /data/filestore/"
    echo "Restoring database from dump..."
# 3. Restore database from dump
if [ -f "$RESTORE_TEMP_DIR/backup/db/odoo_db.dump" ]; then
  cat "$RESTORE_TEMP_DIR/backup/db/odoo_db.dump" | \
    docker exec -i "$DB_CONTAINER_ID" pg_restore -U odoo -d "$PROJECT_NAME" --clean
else
  echo "Database dump not found in backup. Skipping database restore."
fi

echo "Cleaning up..."
rm -rf "$RESTORE_TEMP_DIR"

echo "Restore complete for $PROJECT_NAME!"
