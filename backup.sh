#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/sovereign-stack"
BACKUP_DIR="/var/backups/sovereign-stack"
DATE=$(date +%F)

mkdir -p "${BACKUP_DIR}"

# PostgreSQL veritabanı dökümü
docker exec nextcloud-db pg_dump -U nextcloud nextcloud > "${STACK_DIR}/data/nextcloud_db_${DATE}.sql"

# Tüm veri dizinini ve ayarları sıkıştır
tar -czf "${BACKUP_DIR}/sovereign-backup-${DATE}.tar.gz" \
    "${STACK_DIR}/data" \
    "${STACK_DIR}/site" \
    "${STACK_DIR}/.env"

# Geçici SQL dosyasını ve 7 günden eski arşivleri sil
rm -f "${STACK_DIR}/data/nextcloud_db_${DATE}.sql"
find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +7 -delete
