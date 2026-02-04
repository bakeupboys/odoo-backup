#!/bin/bash
set -e

# Usage: ./show.sh /path/to/odoo/instance
TARGET_DIR="$1"

if [ -z "$TARGET_DIR" ]; then
    echo "Error: No target directory provided."
    echo "Usage: $0 /path/to/odoo/instance"
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


# Show restic snapshots using Docker
docker run --rm \
    --env-file "$CONFIG_FILE" \
    -v "$HOME/.ssh:/ssh:ro" \
    --entrypoint sh \
    restic/restic \
    -c "mkdir -p ~/.ssh && cp /ssh/* ~/.ssh/ && restic snapshots --json" \
| jq -r '.[] | "ID: \(.short_id) | Date: \(.time) | Tags: \(.tags | join(", ")) | Paths: \(.paths | join(", "))"'
