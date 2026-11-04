#!/usr/bin/env bash
# VAISASTRAM Database Restore Procedure
# Restores a custom-format dump into the target database.

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <path_to_backup.dump> [target_database_name]"
  exit 1
fi

BACKUP_FILE="$1"
DATABASE_NAME="${2:-${POSTGRES_DB:-vaisastram_production}}"

if [ ! -f "${BACKUP_FILE}" ]; then
  echo "Error: Backup file '${BACKUP_FILE}' not found."
  exit 1
fi

echo "WARNING: Restoring will overwrite existing tables in '${DATABASE_NAME}'."
read -p "Type 'RESTORE' to proceed: " CONFIRMATION

if [ "${CONFIRMATION}" != "RESTORE" ]; then
  echo "Aborted."
  exit 0
fi

echo "Restoring database from '${BACKUP_FILE}'..."

if [ -n "${DATABASE_URL:-}" ]; then
  pg_restore --clean --if-exists --no-owner --no-privileges -d "${DATABASE_URL}" "${BACKUP_FILE}"
else
  pg_restore --clean --if-exists --no-owner --no-privileges -d "${DATABASE_NAME}" "${BACKUP_FILE}"
fi

echo "Database restoration completed successfully."
echo "Running audit integrity verification..."
bin/rails runner "puts Audit::IntegrityVerifier.verify_chain('system:global').valid? ? 'Integrity verified' : 'Integrity errors detected'"
