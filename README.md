# setup-vpn-full — Portable One-Click VPN & Telegram Bot Installer

Fresh-VPS installer: SSH/Dropbear, Xray (VMess/VLESS/Trojan/Shadowsocks), WS-bridge,
Nginx stream/HTTP, SlowDNS (VayDNS) + UDP-Custom, OpenVPN, auto-SSL, dan
bot Telegram sebagai panel kontrol.

## Fitur
- Support Ubuntu 20.04–24.04 & Debian 11–13, RAM 512MB+
- Tanpa hardcode token/admin/domain — semua diminta saat install
- Protokol: SSH/Dropbear, VMess, VLESS, Trojan, Shadowsocks, OpenVPN (UDP 1194)
- SlowDNS VayDNS (UDP/TCP 53) + UDP-Custom (UDP 36712)
- Bot Telegram: buat akun, limit IP anti-false-lock 1 HP, kuota, speed limit, injeksi bug host, multi-server (VPS remote)
- Auto-heal service, live dashboard, backup self-portable

## Persyaratan
- VPS baru (fresh), akses **root**
- Domain sudah diarahkan: **A record → IP VPS**
- Bot Token Telegram (dari @BotFather)
- Admin ID Telegram (numerik, bukan @username)

## Cara pasang
```bash
# Di VPS baru, login sebagai root
wget -qO /root/setup-vpn-full.sh https://raw.githubusercontent.com/sunekugg/tunelv2/main/setup-vpn-full.sh
bash /root/setup-vpn-full.sh
```

Installer akan menanyakan tiga hal:
```
Masukkan Bot Token Telegram : <token dari @BotFather>
Masukkan Admin ID Telegram  : <ID numerik admin>
Masukkan Domain VPS (A Rec) : <domain, contoh vpn.example.com>
```

Ketiganya wajib diisi — bila kosong installer berhenti. Setelah itu proses jalan
otomatis: pre-flight (cek DNS, IPv6, mirror apt), pasang semua paket & service,
terbitkan SSL, lalu aktifkan seluruh service. Durasi tergantung spek VPS.

## Setelah install
Installer mencetak ringkasan: domain, lokasi/ISP VPS, status tiap service, dan
public key. Bot Telegram langsung aktif — buka chat bot, kirim `/start`, menu
utama muncul.

Cek status service kapan saja:
```bash
systemctl status vpn-telegram-bot   # bot panel
systemctl status dropbear xray nginx vpn-ws-bridge vpn-proto-daemons
```

Lihat log bot:
```bash
journalctl -u vpn-telegram-bot -f
```

## Lokasi file penting
| Path | Isi |
|---|---|
| `/etc/vpn-bot/config.env` | Bot token, admin ID, domain (chmod 600) |
| `/etc/vpn-bot/vpn_data.db` | Database akun & sesi (chmod 600) |
| `/etc/vpn-bot/bot.py` | Kode bot panel |
| `/etc/vpn-bot/vpn_engine.py` | Engine backend (akun SSH/Xray) |
| `/usr/local/etc/xray/config.json` | Config Xray kanonik |

Mengubah token/domain: edit `/etc/vpn-bot/config.env`, lalu
`systemctl restart vpn-telegram-bot`.

## Port yang dibuka (ufw)
SSH/Dropbear (22, 90), port web Xray & Nginx (80, 443, 444, 8080, 8443, 2052, 2053,
2082, 2083, 2095, 2096, 8880, 9080, 9088), SlowDNS 53 & 5300 (TCP/UDP),
OpenVPN 1194/tcp, UDP-Custom 36712/udp, Squid 3128, dan rentang
7100–7600/tcp, 7300/tcp, 6000–19999/udp untuk protokol UDP.

## Troubleshooting
- **apt update gagal** — installer sudah menangani mirror internal provider yang mati
  (mis. mirrors.tencentyun.com → 169.254.0.3). Bila tetap gagal, cek DNS VPS.
- **Bot tak merespons** — `journalctl -u vpn-telegram-bot -f`, pastikan token benar.
- **SSL gagal terbit** — pastikan A record domain sudah menunjuk IP VPS sebelum install.
- **UDP-Custom "TIDAK TERPASANG"** — unduhan gagal saat install, jalankan ulang installer.

## Update installer
```bash
cd /root && wget -qO setup-vpn-full.sh https://raw.githubusercontent.com/sunekugg/tunelv2/main/setup-vpn-full.sh
bash /root/setup-vpn-full.sh
```
Installer aman dijalankan ulang (idempoten untuk config & service).

## Catatan teknis (riwayat perbaikan)
- Hapus 60+ fungsi duplikat (`vpn_engine.py`, `bot.py`) — handler lama yang menang
  (aiogram daftar pertama menang)
- Tambah `apply_global_speed_limit` yang hilang → crash saat set speed limit
- Remote nginx fallback: tambah grpc + http2 (gRPC remote VPS berfungsi)
- OpenVPN 2.5+ dinyatakan eksplisit `verify-client-cert require`
- Fitur akun trial & protokol ZiVPN dihapus dari bot & installer
- SSH banner `SSH-2.0-easyPro` tidak lagi diarahkan ke VMess TCP (fix SSL 443)
- Validasi: `bash -n` OK, semua file Python compile OK, audit referensi engine kosong
