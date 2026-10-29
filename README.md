# 🏛️ Sovereign Workplace

**Küçük ve Orta Ölçekli Kurumlar (1–25 Kullanıcı) İçin Veri Egemenliğine Dayalı, Tek Sunuculu Kurumsal İş Yeri Altyapısı.**

Küçük ölçekli kurumların ve ekiplerin; kullanıcı başı aylık abonelik maliyetlerine (Microsoft 365, Google Workspace, Slack, Trello, 1Password) ve üçüncü parti bulut sağlayıcılarının veri bağımlılığına (vendor lock-in) mecbur kalmadan, **tek bir sanal sunucu (VPS)** üzerinde kendi bağımsız dijital çalışma ortamlarını kurmalarını sağlar.

---

## 🎯 Neden Sovereign (Egemen) Mimari?

* **%100 Veri Mülkiyeti:** Şirket içi yazışmalar, finansal tablolar, müşteri e-postaları ve kurumsal parolalar üçüncü parti sunucularda değil, doğrudan kurumun kendi kontrolündeki diskte barındırılır.
* **Sabit ve Öngörülebilir Maliyet:** Kullanıcı sayısı 5'ten 20'ye çıktığında lisans maliyeti katlanmaz; yalnızca sabit VPS donanım maliyeti ödenir.
* **Tek Komutla Otomasyon:** Karmaşık mikroservis ağları yerine, bellek sınırları (`mem_limit`) optimize edilmiş Docker Compose mimarisiyle 5 dakikada ayağa kalkar.

---

## 🧩 Mimari Bileşenler

| Katman | Açık Kaynak / Ücretsiz Çözüm | Karşılık Geldiği Ticari Ürün |
| :--- | :--- | :--- |
| **Dosya, Takvim, Rehber & Görev** | **Nextcloud** (+Talk, Deck, Calendar, Contacts) | Google Drive, Calendar, Slack, Trello |
| **Çevrimiçi Belge Düzenleme** | **OnlyOffice Docs** (Community Edition) | Microsoft 365 (Word, Excel, PowerPoint) |
| **Kurumsal E-Posta Sunucusu** | **Poste.io** (SMTP/IMAP/Rspamd/ClamAV/Webmail) | Exchange Online / Gmail |
| **Kurumsal Parola Kasası** | **Vaultwarden** (Bitwarden uyumlu) | 1Password / Bitwarden Enterprise |
| **Statik Kurumsal Web Sitesi** | **Caddy File Server** | Kurumsal Tanıtım / Portfolyo Sitesi |
| **Servis ve Durum İzleme** | **Uptime Kuma** | Pingdom / Statuspage |
| **Ters Vekil & Otomatik SSL** | **Caddy 2** (HTTP/3 & Let's Encrypt) | Nginx / Cloudflare |

---

## 💻 Önerilen Donanım Gereksinimleri (20 Kullanıcıya Kadar)

* **İşletim Sistemi:** Ubuntu 22.04 LTS veya 24.04 LTS (Temiz kurulum)
* **İşlemci:** 4 vCPU (Minimum) / 6 vCPU (Önerilen)
* **Bellek (RAM):** 8 GB RAM (Minimum) / 16 GB RAM (Önerilen)
* **Depolama:** 250 GB+ NVMe SSD
* **Ağ:** Giden Port 25 (SMTP) açık, temiz statik IPv4 adresi ve rDNS (PTR) yetkisi.

---

## 🌐 Kurulum Öncesi DNS Yapılandırması

Kurulum betiğini çalıştırmadan önce VPS sağlayıcınızın panelinden sunucu IP'nizin **rDNS (PTR)** kaydını `mail.kurum.com` olarak ayarlayın ve DNS panelinize şu kayıtları girin *(Cloudflare kullanıyorsanız tüm kayıtlarda Proxy/Turuncu Bulut kapalı olmalıdır)*:

| Tip | Ad (Host) | Değer / Hedef | Not |
| :--- | :--- | :--- | :--- |
| **A** | `@`, `cloud`, `office`, `mail`, `vault`, `status` | `[SUNUCU_IP_ADRESI]` | Temel servis adresleri |
| **CNAME** | `www` | `kurum.com.` | Ana site yönlendirmesi |
| **CNAME** | `autoconfig`, `autodiscover` | `mail.kurum.com.` | Outlook/Thunderbird otomatik kurulum |
| **MX** | `@` | `mail.kurum.com.` | Öncelik (Priority): `10` |
| **TXT** | `@` | `"v=spf1 mx a:mail.kurum.com ip4:[SUNUCU_IP] -all"` | SPF Kaydı |
| **TXT** | `_dmarc` | `"v=DMARC1; p=quarantine; rua=mailto:postmaster@kurum.com"` | DMARC Kaydı |

---

## 🚀 Hızlı Kurulum (Tek Komut)

Sunucunuza `root` olarak SSH bağlantısı yapın ve repoyu klonlayarak kurulum betiğini çalıştırın:

```bash
git clone https://github.com/KULLANICI_ADINIZ/sovereign-office-stack.git /opt/sovereign-stack
cd /opt/sovereign-stack
chmod +x install.sh
./install.sh kurum.com
```

### Kurulum Betiği Neler Yapar?
1. Sistem paketlerini günceller, 4 GB Swap alanı oluşturur ve `UFW` güvenlik duvarı portlarını yapılandırır.
2. Resmi Docker ve Docker Compose motorunu kurar.
3. `openssl` ile tüm veritabanı ve yönetici parolalarını rastgele üretip `.env` dosyasına işler.
4. Tüm servisleri başlatır ve SSL sertifikalarını otomatik alır.
5. Nextcloud içine **OnlyOffice, Mail, Calendar, Contacts ve Deck** eklentilerini kurar; Nextcloud ile OnlyOffice arasındaki JWT anahtarlarını iç ağ üzerinden otomatik bağlar.
6. Her gece saat 03:00'te çalışacak otomatik veritabanı ve dosya yedekleme görevini (`/etc/cron.daily/sovereign-backup`) tanımlar.
7. Üretilen tüm yönetici şifrelerini `kurulum-bilgileri.txt` dosyasına kaydeder ve ekrana yazdırır.

---

## ⚙️ Kurulum Sonrası Son Adım (Poste.io DKIM)

1. Tarayıcınızdan `[https://mail.kurum.com/admin/install/server](https://mail.kurum.com/admin/install/server)` adresine giderek ilk e-posta yönetici hesabınızı oluşturun.
2. Sol menüden **Virtual domains** → `kurum.com` → **DKIM key** sekmesine girip **Create a new key** butonuna tıklayın ve üretilen TXT kaydını DNS panelinize ekleyin.
3. **System settings** → **TLS certificate** menüsünden `mail.kurum.com` için Let's Encrypt sertifikasını etkinleştirin.

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) altında açık kaynaklı olarak sunulmaktadır.
