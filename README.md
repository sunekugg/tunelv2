# setup-vpn-full — Portable One-Click VPN & Telegram Bot Installer

Fresh-VPS installer: SSH/Dropbear, Xray (VMess/VLESS/Trojan/SS), WS-bridge, Nginx stream/HTTP, auto-SSL, Telegram bot panel.

## Fitur
- Support Ubuntu 18.04–24.04 & Debian 10–13, RAM 512MB+
- Tanpa hardcode token/admin/domain — input saat install
- Bot Telegram: buat akun, trial, limit IP anti-false-lock 1 HP, kuota, speed limit, injeksi bug, multi-server (VPS remote)
- Auto-heal service, live dashboard, backup self-portable

## Cara pakai
```bash
# Di VPS baru (root)
wget -qO /root/setup-vpn-full.sh <raw-url> && bash /root/setup-vpn-full.sh
```
Masukkan Bot Token, Admin ID, Domain (A record → IP VPS).

## v18 — Perbaikan
- Hapus 60+ fungsi duplikat (`vpn_engine.py`, `bot.py`) — sebelumnya handler lama yang menang (aiogram daftar pertama menang)
- Tambah `apply_global_speed_limit` yang hilang → crash saat set speed limit
- Remote nginx fallback: tambah grpc + http2 (gRPC remote VPS berfungsi)
- Validasi: `bash -n` OK, semua file Python compile OK, audit referensi engine kosong
