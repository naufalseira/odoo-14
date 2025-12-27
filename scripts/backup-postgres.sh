#!/bin/bash
# =============================================================================
# POSTGRESQL BACKUP SCRIPT FOR ODOO
# =============================================================================
# Usage: ./backup-postgres.sh
# Crontab: 0 19 * * * /home/seira/odoo/scripts/backup-postgres.sh
#          (Daily at 02:00 WIB / 19:00 UTC)
# =============================================================================

set -e

BACKUP_DIR="/home/seira/odoo/backup/postgres"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7
BACKUP_FILE="${BACKUP_DIR}/odoo_${DATE}.dump"

echo "=========================================="
echo "POSTGRESQL BACKUP - $(date)"
echo "=========================================="

# Create backup directory if not exists
mkdir -p "${BACKUP_DIR}"

# Find the PostgreSQL container
DB_CONTAINER=$(docker ps -qf "name=odoo-stack_odoo-db" | head -1)

if [ -z "$DB_CONTAINER" ]; then
    # Try compose-style container name
    DB_CONTAINER=$(docker ps -qf "name=odoo-db" | head -1)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo "ERROR: PostgreSQL container not found"
    exit 1
fi

echo "Database container: ${DB_CONTAINER}"
echo "Backup file: ${BACKUP_FILE}"

# Create backup
echo "Creating backup..."
docker exec "${DB_CONTAINER}" pg_dump -U odoo -Fc postgres > "${BACKUP_FILE}"

# Get backup size
BACKUP_SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
echo "Backup size: ${BACKUP_SIZE}"

# Cleanup old backups
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "*.dump" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
echo "Deleted ${DELETED_COUNT} old backup(s)"

# List current backups
echo ""
echo "Current backups:"
ls -lh "${BACKUP_DIR}"/*.dump 2>/dev/null || echo "No backups found"

echo ""
echo "=========================================="
echo "BACKUP COMPLETE"
echo "=========================================="
