#!/usr/bin/env bash
# ==============================================================================
# Sovereign Office Stack - Otomatik Kurulum Betiği (Ubuntu 22.04 / 24.04 LTS)
# ==============================================================================

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
   echo "HATA: Bu betik root yetkisiyle çalıştırılmalıdır (sudo ./install.sh kurum.com)."
   exit 1
fi

DOMAIN="${1:-}"
if [[ -z "${DOMAIN}" ]]; then
    read -rp "Kurumsal alan adınızı girin (örn: kurum.com): " DOMAIN
fi

if [[ -z "${DOMAIN}" ]]; then
    echo "HATA: Geçerli bir alan adı girmediniz."
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="${REPO_DIR}/kurulum-bilgileri.txt"

echo "=================================================================="
echo " Sovereign Office Stack Kurulumu Başlıyor: ${DOMAIN}"
echo " Çalışma Dizini: ${REPO_DIR}"
echo "=================================================================="

# 1. Sistem Güncellemesi ve Temel Paketler
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git ufw fail2ban openssl ca-certificates

hostnamectl set-hostname "mail.${DOMAIN}"

# 2. 4 GB Swap Alanı
if [[ ! -f /swapfile ]]; then
    echo "[+] 4 GB Swap alanı oluşturuluyor..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

# 3. UFW Güvenlik Duvarı
echo "[+] UFW güvenlik duvarı yapılandırılıyor..."
ufw default deny incoming
ufw default allow outgoing
for port in 22/tcp 80/tcp 443/tcp 443/udp 25/tcp 110/tcp 143/tcp 465/tcp 587/tcp 993/tcp 995/tcp; do
    ufw allow "${port}"
done
ufw --force enable

# 4. Docker Kurulumu
if ! command -v docker &> /dev/null; then
    echo "[+] Docker kuruluyor..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

# 5. Veri Dizinleri ve .env Üretimi
cd "${REPO_DIR}"
mkdir -p data/{caddy,poste,postgres,nextcloud,onlyoffice,vaultwarden,uptime-kuma}
mkdir -p /var/backups/sovereign-stack

if [[ ! -f .env ]]; then
    echo "[+] .env dosyası ve kriptografik parolalar üretiliyor..."
    cp .env.example .env

    NC_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
    DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
    REDIS_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
    JWT_SEC=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
    VW_TOKEN=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

    sed -i "s/kurum.com/${DOMAIN}/g" .env
    sed -i "s/CHANGE_ME_NC_PASSWORD/${NC_PASS}/g" .env
    sed -i "s/CHANGE_ME_DB_PASSWORD/${DB_PASS}/g" .env
    sed -i "s/CHANGE_ME_REDIS_PASSWORD/${REDIS_PASS}/g" .env
    sed -i "s/CHANGE_ME_JWT_SECRET/${JWT_SEC}/g" .env
    sed -i "s/CHANGE_ME_VW_TOKEN/${VW_TOKEN}/g" .env
    chmod 600 .env
fi

# .env değişkenlerini içeri aktar
set -a
source .env
set +a

# 6. Konteynerların Başlatılması
echo "[+] Servisler başlatılıyor..."
docker compose up -d

# 7. Nextcloud Hazırlık Kontrolü
echo "[+] Nextcloud veritabanı kurulumu bekleniyor..."
MAX_RETRIES=40
COUNT=0
until docker exec -u www-data nextcloud-app php occ status 2>/dev/null | grep -q "installed: true"; do
    sleep 5
    COUNT=$((COUNT + 1))
    if [[ "${COUNT}" -ge "${MAX_RETRIES}" ]]; then
        echo "UYARI: Nextcloud kurulumu zaman aşımına uğradı."
        break
    fi
    echo "    ... Nextcloud hazırlanıyor (${COUNT}/${MAX_RETRIES})"
done

# 8. Nextcloud & OnlyOffice Otomatik Entegrasyonu
echo "[+] Nextcloud kurumsal eklentileri ve OnlyOffice bağlantısı yapılandırılıyor..."
docker exec -u www-data nextcloud-app php occ config:system:set allow_local_remote_servers --value=true --type=boolean
docker exec -u www-data nextcloud-app php occ config:system:set trusted_proxies 0 --value="172.16.0.0/12"
docker exec -u www-data nextcloud-app php occ config:system:set default_phone_region --value="TR"
docker exec -u www-data nextcloud-app php occ background:cron
docker exec -u www-data nextcloud-app php occ db:add-missing-indices

for app in onlyoffice mail calendar contacts deck; do
    docker exec -u www-data nextcloud-app php occ app:install "${app}" || true
done

docker exec -u www-data nextcloud-app php occ config:app:set onlyoffice DocumentServerUrl --value="https://office.${DOMAIN}/"
docker exec -u www-data nextcloud-app php occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice/"
docker exec -u www-data nextcloud-app php occ config:app:set onlyoffice StorageUrl --value="http://nextcloud/"
docker exec -u www-data nextcloud-app php occ config:app:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET}"
docker exec -u www-data nextcloud-app php occ config:app:set onlyoffice jwt_header --value="Authorization"

# 9. Yedekleme Betiğinin Cron'a Eklenmesi
if [[ -f "${REPO_DIR}/scripts/backup.sh" ]]; then
    cp "${REPO_DIR}/scripts/backup.sh" /etc/cron.daily/sovereign-backup
    sed -i "s|/opt/kurumsal-stack|${REPO_DIR}|g" /etc/cron.daily/sovereign-backup
    chmod +x /etc/cron.daily/sovereign-backup
fi

# 10. Kurulum Özeti
cat << EOF > "${CREDENTIALS_FILE}"
==================================================================
 SOVEREIGN OFFICE STACK - YÖNETİCİ BİLGİLERİ (${DOMAIN})
 Kurulum Tarihi: $(date)
==================================================================
1. Kurumsal Web Sitesi : https://${DOMAIN} (Dizin: ${REPO_DIR}/site)
2. Nextcloud           : https://cloud.${DOMAIN}
   Kullanıcı / Parola  : ${NC_ADMIN_USER} / ${NC_ADMIN_PASSWORD}
3. OnlyOffice Docs     : https://office.${DOMAIN} (JWT: ${ONLYOFFICE_JWT_SECRET})
4. Poste.io Mail Admin : https://mail.${DOMAIN}/admin/install/server
   Webmail             : https://mail.${DOMAIN}/webmail
5. Vaultwarden Admin   : https://vault.${DOMAIN}/admin
   Admin Token         : ${VAULTWARDEN_ADMIN_TOKEN}
6. Uptime Kuma         : https://status.${DOMAIN}
==================================================================
EOF
chmod 600 "${CREDENTIALS_FILE}"
cat "${CREDENTIALS_FILE}"install.sh
