## Overview

This project provides a simple, automated backup solution for your Odoo instance using Restic. It securely backs up your database and filestore to a remote location. It is highly opiniated atm and designed to fit my personla needs. Could be that it get's more flexible in the future™.

---

## Assumptions

This script is based on a few assumptions.

1. You have deployed Odoo, PostgreSQL and restic
2. You have an SFTP/SSH backup server that you can reach without password/with SSH keys
   and have everything configured in your config file. This should be the users `.ssh` directory
   that also executes the backups
3. Your staging db has the same name than production but with staging-prefix

## Quick Start

### 1. Clone & Prepare

```sh
git clone <this-repo-url>
cd odoo-backup
cp env.backup /your/docker/directory/.env.backup
# Edit .env.backup with your remote backup and credentials
```

### 2. Configure `.env.backup`

Edit `.env.backup` in your Odoo project root:

```env
RESTIC_REPOSITORY=sftp:backup-server:/home/user/odoo-backups
RESTIC_PASSWORD=your_secure_password
# (Optional) RESTIC_REST_PASSWORD=...
```

### 3. Run the Backup

```sh
./backup.sh 
```

---

## Requirements

- Restic
- Odoo running naitive
- SSH access to remote backup server

---

## Restore

To restore, use Restic to browse and extract files from your backup repository. See [Restic Docs](https://restic.readthedocs.io/en/stable/040_restore.html).


