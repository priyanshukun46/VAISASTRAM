#!/usr/bin/env bash
# VAISASTRAM Database Backup Procedure
# Produces a gzip-compressed, timestamped PostgreSQL custom-format dump including all audit trails and hash chains.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATABASE_NAME="${POSTGRES_DB:-vaisastram_production}"
BACKUP_FILE="${BACKUP_DIR}/${DATABASE_NAME}_${TIMESTAMP}.dump"
LOG_FILE="${BACKUP_DIR}/backup.log"

mkdir -p "${BACKUP_DIR}"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting database backup for '${DATABASE_NAME}'..." | tee -a "${LOG_FILE}"

if [ -n "${DATABASE_URL:-}" ]; then
  pg_dump --format=custom --no-owner --no-privileges "${DATABASE_URL}" > "${BACKUP_FILE}"
else
  pg_dump --format=custom --no-owner --no-privileges "${DATABASE_NAME}" > "${BACKUP_FILE}"
fi

FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
SHA256_CHECKSUM=$(shasum -a 256 "${BACKUP_FILE}" | cut -d ' ' -f 1)

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Backup completed: ${BACKUP_FILE} (${FILE_SIZE}) [SHA-256: ${SHA256_CHECKSUM}]" | tee -a "${LOG_FILE}"

# Retention policy: prune backups older than 30 days
find "${BACKUP_DIR}" -name "${DATABASE_NAME}_*.dump" -type f -mtime +30 -delete
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Pruned backups older than 30 days." | tee -a "${LOG_FILE}"
