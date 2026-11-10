#!/usr/bin/env bash
# ==============================================================================
#  PORTABLE ONE-CLICK VPN & TELEGRAM BOT INSTALLER (FRESH VPS READY)
#  Support: Ubuntu 18.04 - 24.04 & Debian 10 - 13 (Semua Spesifikasi RAM/CPU)
#  Tanpa Hardcode Bot Token, Admin ID, atau Domain (Input Saat Install)
# ==============================================================================
set -e
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /var/log/xray /etc/xray/certs /etc/dropbear /var/www/html

clear
echo "========================================================================"
echo "      INSTALASI PORTABLE SERVER VPN & BOT TELEGRAM (SEKALI PASANG)      "
echo "========================================================================"
read -rp "Masukkan Bot Token Telegram : " BOT_TOKEN
read -rp "Masukkan Admin ID Telegram  : " ADMIN_ID
read -rp "Masukkan Domain VPS (A Rec) : " DOMAIN

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" || -z "$DOMAIN" ]]; then
    echo "Error: Bot Token, Admin ID, dan Domain wajib diisi!"
    exit 1
fi

# 1. Buka Paksa Kunci APT/DPKG (Mengatasi lock-frontend PID 1410 di VPS Baru)
echo "[1/6] Membebaskan kunci APT/DPKG & mengoptimasi Swap RAM..."
systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service apt-daily.service apt-daily-upgrade.service >/dev/null 2>&1 || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service >/dev/null 2>&1 || true
killall -9 apt apt-get dpkg unattended-upgr >/dev/null 2>&1 || true
sleep 1
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
dpkg --configure -a --force-confdef --force-confold >/dev/null 2>&1 || true

systemctl stop systemd-resolved >/dev/null 2>&1 || true
systemctl disable systemd-resolved >/dev/null 2>&1 || true
rm -f /etc/resolv.conf
echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

ARCH_RAW=$(uname -m)
if [[ "$ARCH_RAW" == "x86_64" ]]; then ARCH="64"; else ARCH="arm64-v8a"; fi

# Unduh Xray dengan fallback multi-mirror (GitHub kadang terblokir di VPS ID)
fetch_xray() {
    local arch="$1" url tmp="/tmp/xray.zip"
    url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    rm -f "$tmp"
    if wget -q --timeout=60 -O "$tmp" "$url"; then return 0; fi
    if wget -q --timeout=90 -O "$tmp" "https://ghproxy.com/$url"; then return 0; fi
    if [[ -f /root/xray-linux-${arch}.zip ]]; then
        cp -f "/root/xray-linux-${arch}.zip" "$tmp"; return 0
    fi
    return 1
}

VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "kvm")

# Buat Auto-Swap 1 GB di awal agar VPS RAM 512MB tidak pernah stuck/freeze
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [[ "$VIRT_TYPE" != "openvz" && "$VIRT_TYPE" != "lxc" ]]; then
    if [[ "$TOTAL_RAM" -lt 2000 ]] && [[ $(swapon --show | wc -l) -eq 0 ]]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 >/dev/null 2>&1
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile >/dev/null 2>&1 || true
        grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    cat << 'EOS' > /etc/sysctl.d/99-vpn-hardening.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
EOS
    sysctl --system >/dev/null 2>&1 || true
fi

# 2. Instalasi Paket Dasar (Support Ubuntu <= 24.04 & Debian <= 13)
echo "[2/6] Menginstal paket sistem & dependensi..."
apt-get update -y -o DPkg::Lock::Timeout=120
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o DPkg::Lock::Timeout=120 \
    curl wget jq git unzip tar socat cron net-tools lsof psmisc \
    iptables iptables-persistent netfilter-persistent fail2ban certbot \
    nginx openssh-server dropbear squid openvpn easy-rsa \
    build-essential zlib1g-dev bzip2 python3 python3-pip python3-venv \
    sqlite3 bc vnstat wondershaper logrotate qrencode openssl >/dev/null 2>&1 || true
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    libnginx-mod-stream >/dev/null 2>&1 || \
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    nginx-full >/dev/null 2>&1 || true
apt-get install -y -o DPkg::Lock::Timeout=60 libcrypt-dev python3-full >/dev/null 2>&1 || true

PUBLIC_IP=$(curl -s4 --max-time 5 ifconfig.me || curl -s4 --max-time 5 api.ipify.org || echo "127.0.0.1")
GEO_JSON=$(curl -s --max-time 5 https://ipinfo.io/json || echo "{}")
VPS_CITY=$(echo "$GEO_JSON" | jq -r '.city // "Singapore"')
VPS_ISP=$(echo "$GEO_JSON" | jq -r '.org // "Cloud ISP"' | sed 's/^AS[0-9]* //')

cat << EOC > /etc/vpn-bot/config.env
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
DOMAIN="$DOMAIN"
PUBLIC_IP="$PUBLIC_IP"
VPS_CITY="$VPS_CITY"
VPS_ISP="$VPS_ISP"
ARCH="$ARCH"
VIRT_TYPE="$VIRT_TYPE"
EOC

if [[ ! -f /etc/vpn-bot/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /etc/vpn-bot/id_ed25519 -C "vpn-bot-master" >/dev/null 2>&1
    chmod 600 /etc/vpn-bot/id_ed25519 && chmod 644 /etc/vpn-bot/id_ed25519.pub
fi

cat << 'EOF_EMBED_FILE' > /etc/issue.net
<p style="text-align:center"><b><br>
<br><font color='#FF8A00'><b>╔══════════ ✦ ══════════╗</b></font><br>
<br><font color='#FF4FD8'><b>➤ Sᴜɴᴇᴋ VPN Pʀᴇᴍɪᴜᴍ ◀</b></font><br>
<br><font color='#FF8A00'><b>╚══════════════════════╝</b></font><br>
<br><font color='#00E5FF'>➤ Aᴋᴜɴ VPN</font><br>
<br><font color='#FF5252'>➤ Nᴏ DDOS</font><br>
<br><font color='#B2FF59'>➤ Nᴏ Tᴏʀʀᴇɴᴛ</font><br>
<br><font color='#40C4FF'>➤ Nᴏ Hᴀᴄᴋɪɴɢ</font><br>
<br><font color='#FF80AB'>➤ Nᴏ Pᴏʀɴ</font><br>
<br><font color='#FFEA00'>➤ Mᴇʟᴀɴɢɢᴀʀ = Bᴀɴɴᴇᴅ!</font><br>
<br><font color='#FF8A00'><b>╔══════════ ✦ ══════════╗</b></font><br>
<br><font color='#FF4FD8'><b>📶 ID • SSH & V2RAY</b></font><br>
<br><font color='#00E5FF'><b>➤ Bɪᴢɴᴇᴛ</b></font><br>
<br><font color='#00E5FF'><b>➤ HᴇʀZᴀ </b></font><br>
<br><font color='#00E5FF'><b>➤ Iᴋᴅ</b></font><br>
<br><font color='#B2FF59'><b>🇮🇩 Sᴇʀᴠᴇʀ Iɴᴅᴏɴᴇsɪᴀ (ID)</b></font><br>
<br><font color='#FFEA00'>├ 💵 8K • 30 Hᴀʀɪ • 2 Dᴇᴠɪᴄᴇ</font><br>
<br><font color='#FF4FD8'><b>➤ Bᴜʏ Hᴜʙ ◀</b></font><br>
<br><font color='#FFEA00'><b>➤ wa.me/6287711905367</b></font><br>
<br><font color='#00E5FF'><b>➤ Gʀᴜᴘ Wʜᴀᴛsᴀᴘᴘ</b></font><br>
<br><font color='#FFEA00'><b>➤ https://chat.whatsapp.com/IhmA7LhtmUbH0uMvJnkcPh?s=cl&p=a&mlu=4&ilr=4</b></font><br>
<br><font color='#FFEA00'><b>➤ @Sᴜɴᴇᴋ 2026</b></font><br>
<br><font color='#FF8A00'><b>╚══════════════════════╝</b></font><br>
</p><br>
EOF_EMBED_FILE
chmod +x /etc/issue.net 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/ws-bridge.py
#!/usr/bin/env python3
import asyncio
import base64
import json
import os
import re
import sqlite3
import time

MAP_LOG = "/var/log/vpn-ws-map.log"
PORT_BW_FILE = "/var/log/vpn-port-bw.json"
PORT_BYTES_MEM = {}
LAST_BW_FLUSH = 0.0


def atomic_write_json(path, data):
    """Tulis JSON secara atomik: proses mati di tengah tak akan menyisakan file korup."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)

XRAY_ROUTES = {
    "/vmess": 10001,
    "/upvmess": 10003,
    "/vless": 10004,
    "/upvless": 10006,
    "/trojan": 10007,
    "/uptrojan": 10009,
    "/ss-ws": 10010,
}

def record_port_ip(lport: int, real_ip: str, target_type: str = "ssh"):
    try:
        with open(MAP_LOG, "a") as f:
            f.write(f"{int(time.time())}|{lport}|{real_ip}|{target_type}\n")
    except Exception:
        pass

def add_port_bytes(lport: int, nbytes: int):
    global LAST_BW_FLUSH
    if not lport or nbytes <= 0:
        return
    PORT_BYTES_MEM[str(lport)] = PORT_BYTES_MEM.get(str(lport), 0) + nbytes
    now = time.time()
    if now - LAST_BW_FLUSH >= 3.0:
        LAST_BW_FLUSH = now
        try:
            atomic_write_json(PORT_BW_FILE, PORT_BYTES_MEM)
        except Exception:
            pass

def extract_real_ip_from_headers(headers_text: str, default_ip: str) -> str:
    for hdr in ("cf-connecting-ip", "true-client-ip", "x-real-ip", "x-forwarded-for"):
        m = re.search(rf"(?im)^{hdr}\s*:\s*([^\r\n,]+)", headers_text)
        if m:
            cand = m.group(1).strip()
            if cand and not cand.startswith("127."):
                return cand
    return default_ip

def generate_sub_response(clean_path: str) -> bytes:
    uname = clean_path.split("/sub/", 1)[1].strip("/")
    if not uname or not os.path.exists("/etc/vpn-bot/vpn_data.db"):
        return b"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"
    conn = sqlite3.connect("/etc/vpn-bot/vpn_data.db", timeout=15)
    conn.row_factory = sqlite3.Row
    try:
        acc = conn.execute("SELECT * FROM accounts WHERE username=?", (uname,)).fetchone()
        if not acc:
            return b"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()
        def_bug_row = conn.execute("SELECT value FROM settings WHERE key='bug_host'").fetchone()
    finally:
        # tutup koneksi di SEMUA jalur agar tak bocor saat query gagal
        conn.close()

    domain = srv["host"]
    secret = acc["secret"]
    proto = acc["protocol"]
    bug = (acc["custom_bug"] if "custom_bug" in acc.keys() and acc["custom_bug"] else (def_bug_row["value"] if def_bug_row else domain)) or domain
    mode = acc["bug_mode"] if "bug_mode" in acc.keys() and acc["bug_mode"] else "sni"

    if mode == "wildcard" and bug != domain:
        addr, sni = bug, f"{bug}.{domain}"
    elif mode == "sni" and bug != domain:
        addr, sni = domain, bug
    elif mode == "cdn" and bug != domain:
        addr, sni = bug, domain
    else:
        addr, sni = domain, domain

    if proto == "trojan":
        l_tls = f"trojan://{secret}@{addr}:443?security=tls&sni={sni}&type=ws&host={sni}&path=%2Ftrojan#{uname}-TLS"
        l_ntls = f"trojan://{secret}@{addr}:80?security=none&type=ws&host={sni}&path=%2Ftrojan#{uname}-NTLS"
    elif proto == "vless":
        l_tls = f"vless://{secret}@{addr}:443?encryption=none&security=tls&sni={sni}&type=ws&host={sni}&path=%2Fvless#{uname}-TLS"
        l_ntls = f"vless://{secret}@{addr}:80?encryption=none&security=none&type=ws&host={sni}&path=%2Fvless#{uname}-NTLS"
    else:
        def b64v(p, tls_v):
            o = {"v":"2","ps":f"{uname}-{'TLS' if tls_v=='tls' else 'NTLS'}","add":addr,"port":str(p),"id":secret,"aid":"0","net":"ws","path":"/vmess","type":"none","host":sni,"sni":sni if tls_v=="tls" else "","tls":tls_v}
            return "vmess://" + base64.b64encode(json.dumps(o, separators=(",",":")).encode()).decode()
        l_tls, l_ntls = b64v(443, "tls"), b64v(80, "none")

    body = base64.b64encode(f"{l_tls}\n{l_ntls}".encode()).decode().encode()
    return (
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Type: text/plain; charset=utf-8\r\n"
        b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        b"Connection: close\r\n\r\n" + body
    )

async def raw_pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, lport: int = 0):
    try:
        while True:
            chunk = await reader.read(16384)
            if not chunk:
                break
            if lport:
                add_port_bytes(lport, len(chunk))
            writer.write(chunk)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

async def handle_client(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
    peer = client_writer.get_extra_info("peername")
    real_ip = peer[0] if peer else "127.0.0.1"
    real_port = peer[1] if peer and len(peer) > 1 else 0

    try:
        initial = await asyncio.wait_for(client_reader.read(8192), timeout=10.0)
        if not initial:
            client_writer.close()
            return

        if initial.startswith(b"PROXY "):
            nl_idx = initial.find(b"\r\n")
            if nl_idx != -1:
                proxy_line = initial[:nl_idx].decode("latin-1", errors="ignore")
                parts = proxy_line.split()
                if len(parts) >= 5 and parts[2] != "127.0.0.1":
                    real_ip = parts[2]
                if len(parts) >= 5 and parts[4].isdigit():
                    real_port = int(parts[4])
                initial = initial[nl_idx + 2:]
                if not initial:
                    initial = await asyncio.wait_for(client_reader.read(8192), timeout=10.0)

        if not initial:
            client_writer.close()
            return

        if initial.startswith(b"SSH-"):
            backend_reader, backend_writer = await asyncio.open_connection("127.0.0.1", 90)
            sockname = backend_writer.get_extra_info("sockname")
            lport = sockname[1] if sockname else 0
            if lport:
                ip_tag = f"{real_ip}:{real_port}" if real_ip == "127.0.0.1" else real_ip
                record_port_ip(lport, ip_tag, "ssh")
                add_port_bytes(lport, len(initial))
            backend_writer.write(initial)
            await backend_writer.drain()
            await asyncio.gather(raw_pipe(client_reader, backend_writer, lport), raw_pipe(backend_reader, client_writer, lport))
            return

        headers_text = initial.decode("latin-1", errors="ignore")
        real_ip = extract_real_ip_from_headers(headers_text, real_ip)

        clean_path = "/"
        for line in headers_text.splitlines():
            m = re.match(r"^(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT)\s+([^\s\?]+)", line.strip(), re.I)
            if m:
                cand_p = m.group(1).strip()
                if cand_p != "/":
                    clean_path = cand_p
                    break

        if clean_path.startswith("/sub/"):
            resp_bytes = generate_sub_response(clean_path)
            client_writer.write(resp_bytes)
            await client_writer.drain()
            client_writer.close()
            return

        matched_xray_port = None
        for r_path, r_port in XRAY_ROUTES.items():
            if clean_path == r_path or clean_path.startswith(r_path + "/"):
                matched_xray_port = r_port
                break

        if matched_xray_port:
            backend_reader, backend_writer = await asyncio.open_connection("127.0.0.1", matched_xray_port)
            sockname = backend_writer.get_extra_info("sockname")
            lport = sockname[1] if sockname else 0
            if lport:
                ip_tag = f"{real_ip}:{real_port}" if real_ip == "127.0.0.1" else real_ip
                record_port_ip(lport, ip_tag, "xray")
                add_port_bytes(lport, len(initial))
            backend_writer.write(initial)
            await backend_writer.drain()
            await asyncio.gather(raw_pipe(client_reader, backend_writer, lport), raw_pipe(backend_reader, client_writer, lport))
            return

        leftover = b""
        sep_idx = initial.rfind(b"\r\n\r\n")
        if sep_idx != -1 and len(initial) > sep_idx + 4:
            after_hdr = initial[sep_idx + 4:]
            if after_hdr.startswith(b"SSH-"):
                leftover = after_hdr

        client_writer.write(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )
        await client_writer.drain()

        backend_reader, backend_writer = await asyncio.open_connection("127.0.0.1", 90)
        sockname = backend_writer.get_extra_info("sockname")
        lport = sockname[1] if sockname else 0
        if lport:
            ip_tag = f"{real_ip}:{real_port}" if real_ip == "127.0.0.1" else real_ip
            record_port_ip(lport, ip_tag, "ssh")
            add_port_bytes(lport, len(initial))

        if leftover:
            backend_writer.write(leftover)
            await backend_writer.drain()

        await asyncio.gather(raw_pipe(client_reader, backend_writer, lport), raw_pipe(backend_reader, client_writer, lport))
    except Exception:
        try:
            client_writer.close()
        except Exception:
            pass

async def cleanup_map_log_worker():
    while True:
        await asyncio.sleep(600)
        try:
            if os.path.exists(MAP_LOG) and os.path.getsize(MAP_LOG) > 2 * 1024 * 1024:
                with open(MAP_LOG, "r", errors="ignore") as f:
                    lines = f.readlines()[-3000:]
                with open(MAP_LOG, "w") as f:
                    f.writelines(lines)
        except Exception:
            pass

async def main():
    global PORT_BYTES_MEM
    os.makedirs(os.path.dirname(MAP_LOG), exist_ok=True)
    if not os.path.exists(MAP_LOG):
        open(MAP_LOG, "a").close()
    os.chmod(MAP_LOG, 0o666)
    if os.path.exists(PORT_BW_FILE):
        try:
            with open(PORT_BW_FILE, "r") as f:
                PORT_BYTES_MEM = json.load(f)
        except Exception:
            PORT_BYTES_MEM = {}
    asyncio.create_task(cleanup_map_log_worker())
    server = await asyncio.start_server(handle_client, "127.0.0.1", 10015, reuse_port=True)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())

EOF_EMBED_FILE
chmod +x /etc/vpn-bot/ws-bridge.py 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/proto-daemons.py
#!/usr/bin/env python3
import asyncio

async def forward_stream(reader, writer, target_port, is_ohp=False):
    try:
        if is_ohp:
            await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=8.0)
            writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await writer.drain()
        t_reader, t_writer = await asyncio.open_connection("127.0.0.1", target_port)
        async def pump(r, w):
            try:
                while True:
                    d = await r.read(8192)
                    if not d: break
                    w.write(d)
                    await w.drain()
            except Exception:
                pass
            finally:
                try: w.close()
                except Exception: pass
        await asyncio.gather(pump(reader, t_writer), pump(t_reader, writer))
    except Exception:
        try: writer.close()
        except Exception: pass

class DNSForwarderProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport
        # simpan referensi task agar tak di-GC sebelum selesai (pitfall asyncio terdokumentasi)
        self._tasks = set()

    def datagram_received(self, data, addr):
        task = asyncio.create_task(self.handle_dns(data, addr))
        # buang dari set begitu selesai agar set tak tumbuh tanpa batas
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def handle_dns(self, data, client_addr):
        loop = asyncio.get_running_loop()
        try:
            on_reply = loop.create_future()
            class UpstreamProto(asyncio.DatagramProtocol):
                def datagram_received(self, d, a):
                    if not on_reply.done():
                        on_reply.set_result(d)
            t = None
            try:
                t, _ = await loop.create_datagram_endpoint(UpstreamProto, remote_addr=("1.1.1.1", 53))
                t.sendto(data)
                reply = await asyncio.wait_for(on_reply, timeout=3.0)
                self.transport.sendto(reply, client_addr)
            finally:
                # tutup socket upstream di SEMUA jalur (termasuk timeout) agar tak bocor FD
                if t is not None:
                    t.close()
        except Exception:
            pass

async def main():
    servers = []
    for port, ohp in ((9080, True), (9088, True), (1194, False), (1080, False),
                      (7100, False), (7200, False), (7300, False), (7400, False), (7500, False), (7600, False)):
        try:
            servers.append(await asyncio.start_server(lambda r, w, o=ohp: forward_stream(r, w, 90, o), "0.0.0.0", port))
        except Exception:
            pass
    loop = asyncio.get_running_loop()
    for up in (5300, 25000):
        try:
            await loop.create_datagram_endpoint(lambda: DNSForwarderProtocol(), local_addr=("0.0.0.0", up))
        except Exception:
            pass
    await asyncio.Event().wait()

if __name__ == "__main__":
    asyncio.run(main())


EOF_EMBED_FILE
chmod +x /etc/vpn-bot/proto-daemons.py 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/vpn_engine.py
#!/usr/bin/env python3
import base64
import calendar
import html
import json
import os
import re
import shutil
import subprocess
import time

XRAY_CONFIG = "/etc/xray/config.json"
XRAY_ACCESS_LOG = "/var/log/xray/access.log"
DROPBEAR_LOG = "/var/log/dropbear.log"
WS_MAP_LOG = "/var/log/vpn-ws-map.log"
ACTIVE_BRIDGE_JSON = "/var/log/vpn-bot/active_bridge.json"
STATE_FILE = "/var/log/vpn-bot/session_state.json"
LOCKED_PASSWORD = "LOCKED_MULTI_LOGIN_STATE"

_SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,32}$")
_SAFE_SECRET = re.compile(r"^[^'\"\\`$;&|<>\n\r\t]{1,128}$")
_SAFE_DOMAIN = re.compile(r"^[A-Za-z0-9.-]{1,253}$")


def safe_username(name: str) -> str:
    """Validasi username Linux/Xray. Raise ValueError bila mengandung karakter shell."""
    if not isinstance(name, str) or not _SAFE_NAME.match(name):
        raise ValueError(f"Username tidak valid: {name!r}")
    return name


def safe_secret(secret: str) -> str:
    """Validasi password/UUID sebelum masuk shell. Tanpa quote/apostrophe/backtick."""
    if not isinstance(secret, str) or not _SAFE_SECRET.match(secret):
        raise ValueError("Password/UUID mengandung karakter yang tidak diizinkan.")
    return secret


def safe_domain(domain: str) -> str:
    """Validasi domain/FQDN sebelum masuk certbot/openssl/sed."""
    if not isinstance(domain, str) or not _SAFE_DOMAIN.match(domain) or ".." in domain:
        raise ValueError(f"Domain tidak valid: {domain!r}")
    return domain


def sh_quote(value: str) -> str:
    """Quote aman untuk disuntik di dalam single-quote shell: 'foo' -> 'foo'\''foo'."""
    return "'" + str(value).replace("'", "'\\''") + "'"


def atomic_write_json(path, data):
    """Tulis JSON secara atomik: proses mati di tengah tak akan menyisakan file korup."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def run_cmd(cmd):
    return subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def run_argv(argv, timeout=None):
    """Jalankan perintah TANPA shell — aman untuk username/password dari input user."""
    try:
        return subprocess.run(argv, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    except Exception as e:
        class _R:
            returncode = 1
            stdout = ""
            stderr = str(e)
        return _R()

def load_xray_config():
    with open(XRAY_CONFIG, "r") as f:
        return json.load(f)

def save_and_reload_xray(cfg):
    backup_path = XRAY_CONFIG + ".bak"
    shutil.copyfile(XRAY_CONFIG, backup_path)
    with open(XRAY_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2)
    run_cmd("systemctl restart xray")
    return True, "OK"

def kill_ssh_sessions(username):
    safe_username(username)
    run_argv(["pkill", "-9", "-u", username])
    if os.path.exists(DROPBEAR_LOG):
        out = run_cmd(f"grep -F \"for '{username}'\" {DROPBEAR_LOG} | tail -n 100").stdout
        pids = set()
        for line in out.splitlines():
            m = re.search(r"\[(\d+)\]", line)
            if m:
                pids.add(m.group(1))
        for pid in pids:
            if not pid.isdigit():
                continue
            cmdline = run_cmd(f"ps -p {pid} -o comm=").stdout.strip()
            if "dropbear" in cmdline:
                run_argv(["kill", "-9", pid])

def create_ssh_user(username, password, exp_date_str):
    safe_username(username)
    safe_secret(password)
    kill_ssh_sessions(username)
    run_argv(["userdel", "-f", username])
    res = run_argv(["useradd", "-e", exp_date_str, "-s", "/bin/false", "-M", username])
    if res.returncode != 0:
        return False
    p = subprocess.Popen(["chpasswd", "-c", "SHA512"], stdin=subprocess.PIPE, text=True)
    p.communicate(f"{username}:{password}\n")
    return True




def add_xray_user(proto, username, uuid_str):
    safe_username(username)
    safe_secret(uuid_str)
    cfg = load_xray_config()
    for ib in cfg.get("inbounds", []):
        if ib.get("protocol") == proto:
            clients = ib["settings"].get("clients", [])
            clients = [c for c in clients if c.get("email") != username]
            if proto == "vmess":
                clients.append({"id": uuid_str, "alterId": 0, "email": username})
            elif proto == "vless":
                clients.append({"id": uuid_str, "email": username})
            elif proto == "trojan":
                clients.append({"password": uuid_str, "email": username})
            ib["settings"]["clients"] = clients
    return save_and_reload_xray(cfg)

def remove_xray_user(proto, username):
    safe_username(username)
    cfg = load_xray_config()
    changed = False
    for ib in cfg.get("inbounds", []):
        if ib.get("protocol") == proto:
            clients = ib["settings"].get("clients", [])
            new_clients = [c for c in clients if c.get("email") != username]
            if len(new_clients) != len(clients):
                changed = True
            ib["settings"]["clients"] = new_clients
    if changed:
        return save_and_reload_xray(cfg)
    return True, "OK"

def clear_all_xray_users(only_usernames=None):
    cfg = load_xray_config()
    for ib in cfg.get("inbounds", []):
        if ib.get("protocol") in ("vmess", "vless", "trojan"):
            if only_usernames is None:
                ib["settings"]["clients"] = []
            else:
                clients = ib["settings"].get("clients", [])
                ib["settings"]["clients"] = [c for c in clients if c.get("email") not in only_usernames]
    return save_and_reload_xray(cfg)

def apply_relay_outbound(relay_dict):
    cfg = load_xray_config()
    outbounds = [o for o in cfg.get("outbounds", []) if o.get("tag") != "relay-out"]
    rules = [r for r in cfg.get("routing", {}).get("rules", []) if r.get("outboundTag") != "relay-out"]

    if relay_dict:
        proto = relay_dict.get("protocol", "vless")
        if proto in ("vless", "vmess"):
            relay_ob = {
                "tag": "relay-out",
                "protocol": proto,
                "settings": {
                    "vnext": [{
                        "address": relay_dict["address"],
                        "port": int(relay_dict["port"]),
                        "users": [{"id": relay_dict["uuid"], "encryption": "none", "alterId": 0}]
                    }]
                },
                "streamSettings": {"network": "ws", "security": "tls", "tlsSettings": {"allowInsecure": True}}
            }
        else:
            relay_ob = {
                "tag": "relay-out",
                "protocol": "socks",
                "settings": {
                    "servers": [{"address": relay_dict["address"], "port": int(relay_dict["port"])}]
                }
            }
        outbounds.insert(0, relay_ob)
        rules.append({
            "type": "field",
            "inboundTag": ["vmess-ws", "vmess-grpc", "vmess-up", "vless-ws", "vless-grpc", "vless-up", "trojan-ws", "trojan-grpc", "trojan-up"],
            "outboundTag": "relay-out"
        })

    cfg["outbounds"] = outbounds
    cfg["routing"]["rules"] = rules
    return save_and_reload_xray(cfg)

def make_vmess_b64(remarks, host, port, uuid_str, net, path, tls_val):
    obj = {
        "v": "2",
        "ps": remarks,
        "add": host,
        "port": str(port),
        "id": uuid_str,
        "aid": "0",
        "net": net,
        "path": path,
        "type": "none",
        "host": host,
        "sni": host,
        "tls": tls_val
    }
    raw = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return "vmess://" + base64.b64encode(raw).decode("utf-8")

def format_ssh_html(host, user, passwd, bug_host="bug.com", ip_limit=2, exp_str="-"):
    h = html.escape
    # Baca public key SlowDNS + NS domain dari server (fallback "-" bila belum terpasang)
    slowdns_pubkey = "-"
    slowdns_ns = f"ns.{host}"
    try:
        with open("/etc/slowdns/server.pub") as _f:
            slowdns_pubkey = h(_f.read().strip())
    except Exception:
        pass
    try:
        with open("/etc/vpn-bot/config.env") as _f:
            for _ln in _f:
                if _ln.startswith("DOMAIN="):
                    _dom = _ln.split("=", 1)[1].strip().strip('"')
                    if _dom:
                        slowdns_ns = f"ns.{_dom}"
    except Exception:
        pass
    top_box = (
        "————————————————————————————————————\n"
        "            SSH/Dropbear\n"
        "————————————————————————————————————\n"
        f"SSH WS        : {h(host)}:80@{h(user)}:{h(passwd)}\n"
        f"SSH SSL       : {h(host)}:443@{h(user)}:{h(passwd)}\n"
        f"SSH UDP       : {h(host)}:1-65535@{h(user)}:{h(passwd)}\n"
        f"SSH SELOWDNS  : ns-{h(host)}:5300@{h(user)}:{h(passwd)}\n"
        "————————————————————————————————————\n"
        f"HOST          : {h(host)}\n"
        f"Username      : {h(user)}\n"
        f"Password      : {h(passwd)}\n"
        f"Limit IP      : {ip_limit} IP\n"
        f"Expired On    : {h(exp_str)}\n"
        "————————————————————————————————————\n"
        "TLS           : 443,8443\n"
        "None TLS      : 80,8080\n"
        "Any           : 2082,2083,8880\n"
        "OpenSSH       : 444\n"
        "Dropbear      : 90\n"
        "SlowDNS       : 53,5300\n"
        "UDP-Custom    : 1-65535\n"
        f"NS SlowDNS    : {h(slowdns_ns)}\n"
        f"PUBLIC KEY    : {slowdns_pubkey}\n"
        "OHP + SSH     : 9080\n"
        "Squid Proxy   : 3128\n"
        "BadVPN UDPGW  : 7100-7600\n"
        "OpenVPN TCP   : 80,1194\n"
        "OpenVPN SSL   : 443\n"
        "OpenVPN UDP   : 25000\n"
        "OpenVPN DNS   : 53\n"
        "OHP + OVPN    : 9088\n"
        "————————————————————————————————————"
    )
    p_ws = "GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    p_enh = f"PATCH / HTTP/1.1[crlf]Host: [host][crlf]Host: {h(bug_host)}[crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    return (
        f"<pre>{top_box}</pre>\n"
        f"<b>Payload WS :</b>\n<code>{p_ws}</code>\n"
        f"<pre>————————————————————————————————————</pre>\n"
        f"<b>Payload ENHANCED :</b>\n<code>{p_enh}</code>\n"
        f"<pre>————————————————————————————————————</pre>"
    )

def format_vmess_html(remarks, city, isp, host, uuid_str, expired, ip_limit=2):
    h = html.escape
    ws_tls = make_vmess_b64(remarks, host, 443, uuid_str, "ws", "/vmess", "tls")
    ws_notls = make_vmess_b64(remarks, host, 80, uuid_str, "ws", "/vmess", "none")
    grpc_tls = make_vmess_b64(remarks, host, 443, uuid_str, "grpc", "vmess", "tls")
    up_tls = make_vmess_b64(remarks, host, 443, uuid_str, "httpupgrade", "/upvmess", "tls")
    up_notls = make_vmess_b64(remarks, host, 80, uuid_str, "httpupgrade", "/upvmess", "none")

    top_box = (
        "————————————————————————————————————\n"
        "               VMESS\n"
        "————————————————————————————————————\n"
        f"Remarks        : {h(remarks)}\n"
        f"CITY           : {h(city)}\n"
        f"ISP            : {h(isp)}\n"
        f"Domain         : {h(host)}\n"
        "Port TLS       : 443,8443\n"
        "Port none TLS  : 80,8080\n"
        "Port any       : 2052,2053,8880\n"
        f"id             : {h(uuid_str)}\n"
        "alterId        : 0\n"
        "Security       : auto\n"
        "network        : ws,grpc,upgrade\n"
        "path ws        : /vmess - /whatever\n"
        "serviceName    : vmess\n"
        "path upgrade   : /upvmess\n"
        f"Limit IP       : {ip_limit} IP\n"
        f"Expired On     : {h(expired)}\n"
        "————————————————————————————————————"
    )
    return (
        f"<pre>{top_box}</pre>\n"
        f"<pre>            VMESS WS TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(ws_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n           VMESS WS NO TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(ws_notls)}</code>\n"
        f"<pre>————————————————————————————————————\n              VMESS GRPC\n————————————————————————————————————</pre>\n"
        f"<code>{h(grpc_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n          VMESS Upgrade TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(up_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n         VMESS Upgrade NO TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(up_notls)}</code>\n"
        f"<pre>————————————————————————————————————</pre>"
    )

def format_vless_html(remarks, city, isp, host, uuid_str, expired, ip_limit=2):
    h = html.escape
    ws_tls = f"vless://{uuid_str}@{host}:443?path=/vless&security=tls&encryption=none&host={host}&type=ws&sni={host}#{remarks}"
    ws_notls = f"vless://{uuid_str}@{host}:80?path=/vless&security=none&encryption=none&host={host}&type=ws#{remarks}"
    grpc_tls = f"vless://{uuid_str}@{host}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless&sni={host}#{remarks}"
    up_tls = f"vless://{uuid_str}@{host}:443?path=/upvless&security=tls&encryption=none&host={host}&type=httpupgrade&sni={host}#{remarks}"
    up_notls = f"vless://{uuid_str}@{host}:80?path=/upvless&security=none&encryption=none&host={host}&type=httpupgrade#{remarks}"

    top_box = (
        "————————————————————————————————————\n"
        "               VLESS\n"
        "————————————————————————————————————\n"
        f"Remarks        : {h(remarks)}\n"
        f"CITY           : {h(city)}\n"
        f"ISP            : {h(isp)}\n"
        f"Domain         : {h(host)}\n"
        "Port TLS       : 443,8443\n"
        "Port none TLS  : 80,8080\n"
        "Port any       : 2052,2053,8880\n"
        f"id             : {h(uuid_str)}\n"
        "Encryption     : none\n"
        "Network        : ws,grpc,upgrade\n"
        "Path ws        : /vless\n"
        "serviceName    : vless\n"
        "Path upgrade   : /upvless\n"
        f"Limit IP       : {ip_limit} IP\n"
        f"Expired On     : {h(expired)}\n"
        "————————————————————————————————————"
    )
    return (
        f"<pre>{top_box}</pre>\n"
        f"<pre>            VLESS WS TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(ws_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n           VLESS WS NO TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(ws_notls)}</code>\n"
        f"<pre>————————————————————————————————————\n              VLESS GRPC\n————————————————————————————————————</pre>\n"
        f"<code>{h(grpc_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n          VLESS Upgrade TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(up_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n         VLESS Upgrade NO TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(up_notls)}</code>\n"
        f"<pre>————————————————————————————————————</pre>"
    )

def format_trojan_html(remarks, city, isp, host, uuid_str, expired, ip_limit=2):
    h = html.escape
    ws_tls = f"trojan://{uuid_str}@{host}:443?path=/trojan&security=tls&host={host}&type=ws&sni={host}#{remarks}"
    grpc_tls = f"trojan://{uuid_str}@{host}:443?mode=gun&security=tls&type=grpc&serviceName=trojan&sni={host}#{remarks}"
    up_tls = f"trojan://{uuid_str}@{host}:443?path=/uptrojan&security=tls&host={host}&type=httpupgrade&sni={host}#{remarks}"

    top_box = (
        "————————————————————————————————————\n"
        "               TROJAN\n"
        "————————————————————————————————————\n"
        f"Remarks      : {h(remarks)}\n"
        f"CITY         : {h(city)}\n"
        f"ISP          : {h(isp)}\n"
        f"Domain       : {h(host)}\n"
        "Port         : 443,8443\n"
        "Port any     : 2052,2053,8880\n"
        f"Key          : {h(uuid_str)}\n"
        "Network      : ws,grpc,upgrade\n"
        "Path ws      : /trojan\n"
        "serviceName  : trojan\n"
        "Path upgrade : /uptrojan\n"
        f"Limit IP     : {ip_limit} IP\n"
        "————————————————————————————————————"
    )
    return (
        f"<pre>{top_box}</pre>\n"
        f"<pre>            TROJAN WS TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(ws_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n              TROJAN GRPC\n————————————————————————————————————</pre>\n"
        f"<code>{h(grpc_tls)}</code>\n"
        f"<pre>————————————————————————————————————\n          TROJAN Upgrade TLS\n————————————————————————————————————</pre>\n"
        f"<code>{h(up_tls)}</code>\n"
        f"<pre>————————————————————————————————————\nExpired On  : {h(expired)}\n————————————————————————————————————</pre>"
    )

def scan_active_sessions():
    now = time.time()
    results = {}

    state = {"xray_offset": 0, "xray_recent": {}, "port_to_user": {}}
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                state.update(json.load(f))
        except Exception:
            pass

    active_bridge = {}
    if os.path.exists(ACTIVE_BRIDGE_JSON):
        try:
            with open(ACTIVE_BRIDGE_JSON, "r") as f:
                active_bridge = json.load(f)
        except Exception:
            active_bridge = {}

    port_to_ip = {}
    if os.path.exists(WS_MAP_LOG):
        out = run_cmd(f"tail -n 4000 {WS_MAP_LOG}").stdout
        for line in out.splitlines():
            parts = line.strip().split("|")
            if len(parts) >= 3:
                try:
                    ts, lport, rip = float(parts[0]), parts[1], parts[2]
                    if now - ts < 86400 and rip:
                        port_to_ip[lport] = rip
                except Exception:
                    pass

    for lport, info in active_bridge.items():
        if info.get("ip"):
            port_to_ip[lport] = info["ip"]

    xray_recent = state.get("xray_recent", {})
    port_to_user = state.get("port_to_user", {})

    if os.path.exists(XRAY_ACCESS_LOG):
        fsize = os.path.getsize(XRAY_ACCESS_LOG)
        last_pos = state.get("xray_offset", 0)
        if fsize < last_pos:
            last_pos = 0
        try:
            with open(XRAY_ACCESS_LOG, "rb") as f:
                f.seek(last_pos)
                for raw in f:
                    try:
                        line = raw.decode("utf-8", errors="ignore")
                    except Exception:
                        continue
                    if "accepted" not in line or "email:" not in line:
                        continue
                    m = re.search(r"from\s+(?:tcp:|udp:)?(\S+)\s+accepted\s+.*?\bemail:\s*(\S+)", line)
                    if not m:
                        continue
                    src_token, email = m.group(1), m.group(2).strip()
                    if ":" in src_token:
                        src_ip, src_port = src_token.rsplit(":", 1)
                    else:
                        src_ip, src_port = src_token, "0"
                    src_ip = src_ip.strip("[]")

                    real_ip = src_ip
                    if src_ip.startswith("127.") or src_ip == "::1":
                        real_ip = port_to_ip.get(src_port, "")

                    if real_ip and not real_ip.startswith("127."):
                        if src_port != "0":
                            port_to_user[src_port] = {"user": email, "ip": real_ip, "ts": now}
                        user_ips = xray_recent.setdefault(email, {})
                        user_ips[real_ip] = now
                state["xray_offset"] = f.tell()
        except Exception:
            pass

    active_xray_ports = {p for p, d in active_bridge.items() if d.get("type") in ("vmess", "vless", "trojan", "ss")}
    cleaned_p2u = {}
    for lport, udata in port_to_user.items():
        if lport in active_xray_ports or (now - udata.get("ts", 0) <= 90):
            cleaned_p2u[lport] = udata
            uname = udata["user"]
            rip = udata["ip"]
            xray_recent.setdefault(uname, {})[rip] = now
            info = results.setdefault(uname, {"ips": set(), "sessions": 0, "last_ip": rip})
            info["ips"].add(rip)
            info["sessions"] += 1
            info["last_ip"] = rip
    state["port_to_user"] = cleaned_p2u

    cleaned_recent = {}
    for uname, ip_dict in xray_recent.items():
        valid_ips = {ip: ts for ip, ts in ip_dict.items() if now - ts <= 90}
        if valid_ips:
            cleaned_recent[uname] = valid_ips
            info = results.setdefault(uname, {"ips": set(), "sessions": 0, "last_ip": ""})
            for ip in valid_ips:
                if ip not in info["ips"]:
                    info["ips"].add(ip)
                    info["sessions"] += 1
                elif info["sessions"] == 0:
                    info["sessions"] = 1
                info["last_ip"] = ip
    state["xray_recent"] = cleaned_recent

    pid_to_user = {}
    port_to_ssh_user = {}

    if os.path.exists(DROPBEAR_LOG):
        db_lines = run_cmd(f"tail -n 2500 {DROPBEAR_LOG}").stdout
        for line in db_lines.splitlines():
            m = re.search(r"\[(\d+)\].*Password auth succeeded for '([^']+)' from ([0-9a-fA-F\.:]+):(\d+)", line)
            if m:
                pid, uname, src_ip, src_port = m.group(1), m.group(2), m.group(3), m.group(4)
                pid_to_user[pid] = uname
                port_to_ssh_user[src_port] = uname

    if os.path.exists("/var/log/auth.log"):
        auth_lines = run_cmd("tail -n 1500 /var/log/auth.log").stdout
        for line in auth_lines.splitlines():
            m_ssh = re.search(r"sshd\[(\d+)\]:\s+Accepted password for (\S+) from (\S+) port (\d+)", line)
            if m_ssh:
                pid, uname, src_ip, src_port = m_ssh.group(1), m_ssh.group(2), m_ssh.group(3), m_ssh.group(4)
                pid_to_user[pid] = uname
                port_to_ssh_user[src_port] = uname

    ss_ssh = run_cmd("ss -tnp '( sport = :90 or sport = :444 or sport = :22 )'").stdout
    for line in ss_ssh.splitlines():
        if "127.0.0.1:90" not in line and ":90 " not in line and ":444 " not in line and ":22 " not in line:
            continue
        m_addr = re.search(r"\S+:(?:90|444|22)\s+([0-9a-fA-F\.\:\[\]]+):(\d+)", line)
        if not m_addr:
            continue
        peer_ip = m_addr.group(1).strip("[]")
        peer_port = m_addr.group(2)
        pids = re.findall(r"pid=(\d+)", line)

        uname = port_to_ssh_user.get(peer_port)
        if not uname:
            for p in pids:
                if p in pid_to_user:
                    uname = pid_to_user[p]
                    break
        if not uname:
            continue

        real_ip = peer_ip
        if peer_ip.startswith("127.") or peer_ip == "::1":
            real_ip = port_to_ip.get(peer_port, peer_ip)

        if real_ip:
            info = results.setdefault(uname, {"ips": set(), "sessions": 0, "last_ip": real_ip})
            info["ips"].add(real_ip)
            info["sessions"] += 1
            info["last_ip"] = real_ip

    try:
        atomic_write_json(STATE_FILE, state)
    except Exception:
        pass

    return results

def get_default_iface():
    out = run_cmd("ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}'").stdout.strip()
    return out if out else "eth0"

def read_cpu_times():
    try:
        with open("/proc/stat", "r") as f:
            line = f.readline()
        parts = [float(x) for x in line.split()[1:]]
        idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
        total = sum(parts)
        return idle, total
    except Exception:
        return 0.0, 1.0

def read_net_bytes(iface):
    try:
        with open(f"/sys/class/net/{iface}/statistics/rx_bytes", "r") as f:
            rx = int(f.read().strip())
        with open(f"/sys/class/net/{iface}/statistics/tx_bytes", "r") as f:
            tx = int(f.read().strip())
        return rx, tx
    except Exception:
        return 0, 0

def format_data_size(num_bytes):
    val = float(num_bytes)
    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if val < 1024.0 or unit == "TiB":
            if unit == "B":
                return f"{int(val)} B"
            return f"{val:.2f} {unit}"
        val /= 1024.0
    return f"{val:.2f} TiB"

def get_vnstat_summary(iface):
    day_bytes = 0
    month_bytes = 0
    try:
        out = run_cmd(f"vnstat -i {iface} --json").stdout.strip()
        if not out:
            out = run_cmd("vnstat --json").stdout.strip()
        if out:
            data = json.loads(out)
            ifaces = data.get("interfaces", [])
            if ifaces:
                traffic = ifaces[0].get("traffic", {})
                days = traffic.get("day", traffic.get("days", []))
                months = traffic.get("month", traffic.get("months", []))
                if days:
                    last_d = days[-1]
                    day_bytes = int(last_d.get("rx", 0)) + int(last_d.get("tx", 0))
                if months:
                    last_m = months[-1]
                    month_bytes = int(last_m.get("rx", 0)) + int(last_m.get("tx", 0))
    except Exception:
        pass
    if day_bytes == 0 and month_bytes == 0:
        rx, tx = read_net_bytes(iface)
        day_bytes = rx + tx
        month_bytes = rx + tx
    return day_bytes, month_bytes

def get_ssl_info():
    cert_file = "/etc/xray/certs/fullchain.pem"
    if not os.path.exists(cert_file):
        return "🔴 Tidak Ada", "-"
    out = run_cmd(f"openssl x509 -in {cert_file} -noout -enddate -issuer 2>/dev/null").stdout
    exp_str = "-"
    issuer = "Self-Signed"
    for line in out.splitlines():
        if line.startswith("notAfter="):
            exp_str = line.split("=", 1)[1].strip()
        elif "Let's Encrypt" in line or "ZeroSSL" in line:
            issuer = "Let's Encrypt"
    return f"🟢 Aktif ({issuer})", exp_str

def get_dashboard_stats():
    iface = get_default_iface()
    idle1, tot1 = read_cpu_times()
    rx1, tx1 = read_net_bytes(iface)
    time.sleep(0.15)
    idle2, tot2 = read_cpu_times()
    rx2, tx2 = read_net_bytes(iface)

    dt = max(1.0, tot2 - tot1)
    cpu_pct = max(0.0, min(100.0, (1.0 - (idle2 - idle1) / dt) * 100.0))

    in_mbps = max(0.0, ((rx2 - rx1) * 8.0) / 0.15 / 1_000_000.0)
    out_mbps = max(0.0, ((tx2 - tx1) * 8.0) / 0.15 / 1_000_000.0)

    ram_used, ram_total, ram_pct = 0, 1, 0.0
    try:
        mem_out = run_cmd("free -m | awk '/^Mem:/ {print $3, $2}'").stdout.strip().split()
        if len(mem_out) >= 2:
            ram_used = int(mem_out[0])
            ram_total = max(1, int(mem_out[1]))
            ram_pct = (ram_used / ram_total) * 100.0
    except Exception:
        pass

    try:
        du = shutil.disk_usage("/")
        disk_used_gb = du.used / (1024 ** 3)
        disk_tot_gb = max(1.0, du.total / (1024 ** 3))
        disk_pct = (du.used / du.total) * 100.0
    except Exception:
        disk_used_gb, disk_tot_gb, disk_pct = 0.0, 1.0, 0.0

    def svc_badge(names):
        for n in names:
            if run_cmd(f"systemctl is-active {n}").stdout.strip() == "active":
                return "🟢 Aktif"
        return "🔴 Mati"

    xray_st = svc_badge(["xray"])
    ssh_st = svc_badge(["ssh", "sshd"])
    db_st = svc_badge(["dropbear"])
    hap_st = svc_badge(["haproxy", "vpn-ws-bridge"])
    ngx_st = svc_badge(["nginx"])
    ssl_st, ssl_exp = get_ssl_info()

    day_b, mth_b = get_vnstat_summary(iface)
    day_gb = day_b / (1024 ** 3)

    return {
        "xray_st": xray_st,
        "ssh_st": ssh_st,
        "db_st": db_st,
        "hap_st": hap_st,
        "ngx_st": ngx_st,
        "ssl_st": ssl_st,
        "ssl_exp": ssl_exp,
        "cpu_pct": f"{cpu_pct:.1f}%",
        "ram_str": f"{ram_used} MB / {ram_total} MB ({ram_pct:.1f}%)",
        "disk_str": f"{disk_used_gb:.0f} GB / {disk_tot_gb:.0f} GB ({disk_pct:.1f}%)",
        "bw_gb_str": f"{day_gb:.2f} GB",
        "in_mbps": f"{in_mbps:.2f} Mbps",
        "out_mbps": f"{out_mbps:.2f} Mbps",
        "vnstat_day": format_data_size(day_b),
        "vnstat_mth": format_data_size(mth_b),
    }


# --- GENERATOR INJECT BUG & MULTI-CLIENT (TLS, NTLS, CLASH YAML, SING-BOX JSON) ---
def compute_bug_target(domain: str, bug: str, mode: str):
    bug = (bug or "").strip()
    if not bug or mode == "default":
        return "Default (Tanpa Bug)", domain, domain
    if mode == "wildcard":
        return "Wildcard (bug.domain)", bug, f"{bug}.{domain}"
    elif mode == "sni":
        return "SNI / SSL (Spoof Bug)", domain, bug
    elif mode == "cdn":
        return "CDN / WS (Direct)", bug, domain
    return "Default (Tanpa Bug)", domain, domain

def build_inject_links_and_yaml(proto: str, uname: str, secret: str, srv_name: str, domain: str, bug: str, mode: str):
    h = html.escape
    mode_lbl, addr, sni = compute_bug_target(domain, bug, mode)
    path_str = f"/{proto}" if proto in ("vmess", "vless", "trojan") else "/"
    enc_path = f"%2F{proto}" if proto in ("vmess", "vless", "trojan") else "%2F"

    if proto == "trojan":
        tls_link = f"trojan://{secret}@{addr}:443?security=tls&sni={sni}&type=ws&host={sni}&path={enc_path}#{uname}-TLS"
        ntls_link = f"trojan://{secret}@{addr}:80?security=none&type=ws&host={sni}&path={enc_path}#{uname}-NTLS"
        yaml_cfg = (
            "proxies:\n"
            f"  - name: \"{uname}-TLS\"\n"
            "    type: trojan\n"
            f"    server: {addr}\n"
            "    port: 443\n"
            f"    password: {secret}\n"
            "    tls: true\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            f"      path: {path_str}\n"
            "      headers:\n"
            f"        Host: {sni}\n\n"
            f"  - name: \"{uname}-NTLS\"\n"
            "    type: trojan\n"
            f"    server: {addr}\n"
            "    port: 80\n"
            f"    password: {secret}\n"
            "    tls: false\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            f"      path: {path_str}\n"
            "      headers:\n"
            f"        Host: {sni}"
        )
    elif proto == "vless":
        tls_link = f"vless://{secret}@{addr}:443?encryption=none&security=tls&sni={sni}&type=ws&host={sni}&path={enc_path}#{uname}-TLS"
        ntls_link = f"vless://{secret}@{addr}:80?encryption=none&security=none&type=ws&host={sni}&path={enc_path}#{uname}-NTLS"
        yaml_cfg = (
            "proxies:\n"
            f"  - name: \"{uname}-TLS\"\n"
            "    type: vless\n"
            f"    server: {addr}\n"
            "    port: 443\n"
            f"    uuid: {secret}\n"
            "    tls: true\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            f"      path: {path_str}\n"
            "      headers:\n"
            f"        Host: {sni}\n\n"
            f"  - name: \"{uname}-NTLS\"\n"
            "    type: vless\n"
            f"    server: {addr}\n"
            "    port: 80\n"
            f"    uuid: {secret}\n"
            "    tls: false\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            f"      path: {path_str}\n"
            "      headers:\n"
            f"        Host: {sni}"
        )
    elif proto == "vmess":
        tls_link = make_vmess_b64(f"{uname}-TLS", addr, 443, secret, "ws", "/vmess", "tls")
        # Override host & sni inside vmess json for custom bug
        obj_tls = {"v":"2","ps":f"{uname}-TLS","add":addr,"port":"443","id":secret,"aid":"0","net":"ws","path":"/vmess","type":"none","host":sni,"sni":sni,"tls":"tls"}
        obj_ntls = {"v":"2","ps":f"{uname}-NTLS","add":addr,"port":"80","id":secret,"aid":"0","net":"ws","path":"/vmess","type":"none","host":sni,"sni":"","tls":"none"}
        tls_link = "vmess://" + base64.b64encode(json.dumps(obj_tls, separators=(",",":")).encode()).decode()
        ntls_link = "vmess://" + base64.b64encode(json.dumps(obj_ntls, separators=(",",":")).encode()).decode()
        yaml_cfg = (
            "proxies:\n"
            f"  - name: \"{uname}-TLS\"\n"
            "    type: vmess\n"
            f"    server: {addr}\n"
            "    port: 443\n"
            f"    uuid: {secret}\n"
            "    alterId: 0\n"
            "    cipher: auto\n"
            "    tls: true\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            "      path: /vmess\n"
            "      headers:\n"
            f"        Host: {sni}\n\n"
            f"  - name: \"{uname}-NTLS\"\n"
            "    type: vmess\n"
            f"    server: {addr}\n"
            "    port: 80\n"
            f"    uuid: {secret}\n"
            "    alterId: 0\n"
            "    cipher: auto\n"
            "    tls: false\n"
            "    udp: true\n"
            "    skip-cert-verify: true\n"
            f"    servername: {sni}\n"
            "    network: ws\n"
            "    ws-opts:\n"
            "      path: /vmess\n"
            "      headers:\n"
            f"        Host: {sni}"
        )
    else:
        # SSH Inject Bug
        tls_link = f"{addr}:443@{uname}:{secret}"
        ntls_link = f"{addr}:80@{uname}:{secret}"
        yaml_cfg = (
            f"# Payload WS (NTLS 80):\n"
            f"GET / HTTP/1.1[crlf]Host: {sni}[crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]\n\n"
            f"# Payload ENHANCED (TLS 443 / Dual Host):\n"
            f"PATCH / HTTP/1.1[crlf]Host: {domain}[crlf]Host: {sni}[crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
        )

    text_out = (
        f"🎯 <b>CONFIG {proto.upper()} — INJECT BUG & MULTI-CLIENT</b>\n"
        "────────────────────────────\n"
        f"• <b>Server:</b> {h(srv_name)} (<code>{h(domain)}</code>)\n"
        f"• <b>Path:</b> <code>{h(path_str)}</code>\n"
        f"• <b>Metode:</b> <code>{h(mode_lbl)}</code>\n"
        f"• <b>Address (Bug):</b> <code>{h(addr)}</code>\n"
        f"• <b>Subdomain (SNI/Host):</b> <code>{h(sni)}</code>\n\n"
        "🔐 <b>1. TLS (Port 443):</b>\n"
        f"<pre><code class=\"language-Tls\">{h(tls_link)}</code></pre>\n\n"
        "🔓 <b>2. NTLS (Port 80):</b>\n"
        f"<pre><code class=\"language-Ntls\">{h(ntls_link)}</code></pre>\n\n"
        "📄 <b>3. YAML (Clash / OpenClash / Mihomo):</b>\n"
        f"<pre><code class=\"language-YAML\">{h(yaml_cfg)}</code></pre>"
    )
    return text_out, tls_link, ntls_link, addr, sni, path_str

def build_singbox_json(proto: str, uname: str, secret: str, domain: str, bug: str, mode: str) -> str:
    _, addr, sni = compute_bug_target(domain, bug, mode)
    path_str = f"/{proto}" if proto in ("vmess", "vless", "trojan") else "/"
    items = []
    for label, port, use_tls in ((f"{uname}-TLS", 443, True), (f"{uname}-NTLS", 80, False)):
        ob = {
            "type": proto if proto in ("vmess", "vless", "trojan") else "ssh",
            "tag": label,
            "server": addr,
            "server_port": port,
        }
        if proto == "trojan":
            ob["password"] = secret
        elif proto in ("vmess", "vless"):
            ob["uuid"] = secret
            if proto == "vmess":
                ob["security"] = "auto"
                ob["alter_id"] = 0
        else:
            ob["user"] = uname
            ob["password"] = secret
        if proto in ("vmess", "vless", "trojan"):
            ob["tls"] = {"enabled": use_tls, "server_name": sni, "insecure": True}
            ob["transport"] = {"type": "ws", "path": path_str, "headers": {"Host": sni}}
        items.append(ob)
    return json.dumps({"outbounds": items}, indent=2)

# --- PARSER INJECT AKUN LUAR (IN-MEMORY / ZERO SAVE) ---
def parse_external_vpn_link(link_str: str):
    import urllib.parse
    link_str = link_str.strip()
    if link_str.startswith("vmess://"):
        b64_part = link_str[8:].strip()
        pad = len(b64_part) % 4
        if pad:
            b64_part += "=" * (4 - pad)
        raw_json = base64.b64decode(b64_part).decode("utf-8", errors="ignore")
        obj = json.loads(raw_json)
        host = obj.get("add") or obj.get("host") or obj.get("sni") or ""
        secret = obj.get("id") or ""
        uname = obj.get("ps") or "External-VMess"
        path = obj.get("path") or "/vmess"
        if not host or not secret:
            raise ValueError("Link VMess tidak lengkap.")
        return {"protocol": "vmess", "username": uname, "secret": secret, "host": host, "path": path}

    elif link_str.startswith(("vless://", "trojan://")):
        proto = "vless" if link_str.startswith("vless://") else "trojan"
        parsed = urllib.parse.urlsplit(link_str)
        secret = urllib.parse.unquote(parsed.username or "")
        host = parsed.hostname or ""
        qs = urllib.parse.parse_qs(parsed.query)
        sni_or_host = (qs.get("sni") or qs.get("host") or [host])[0]
        base_domain = host if not re.match(r"^\d+\.\d+\.\d+\.\d+$", host) else sni_or_host
        path = (qs.get("path") or [f"/{proto}"])[0]
        uname = urllib.parse.unquote(parsed.fragment or f"External-{proto.upper()}")
        if not base_domain or not secret:
            raise ValueError(f"Link {proto.upper()} tidak valid.")
        return {"protocol": proto, "username": uname, "secret": secret, "host": base_domain, "path": path}

    raise ValueError("Format link tidak didukung. Gunakan vmess://, vless://, atau trojan://")

def apply_server_speed(srv_row, mbps: int):
    # PENTING: wondershaper/tc bekerja per-interface, bukan per-user.
    # VPS lokal berbagi interface dgn limit global (apply_global_speed_limit) —
    # set per-server lokal hanya menimpa global, jadi kita tolak dgn pesan jelas.
    if srv_row["is_local"] == 1:
        g = get_int_setting_safe("default_speed_mbps", 0)
        return False, (
            f"VPS Lokal memakai Speed Global ({g if g > 0 else 'Unlimited'} Mbps). "
            "Set limit ini di menu Pengaturan → default_speed_mbps. "
            "Limit per-server hanya berlaku untuk VPS Remote (interface terpisah)."
        )
    import paramiko
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(srv_row["host"], port=srv_row["ssh_port"], username=srv_row["ssh_user"], password=srv_row["ssh_pass"], timeout=10)
        cmd = (
            "IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}'); "
            + (f"wondershaper -a $IFACE -d {mbps*1024} -u {mbps*1024}" if mbps > 0 else "wondershaper -c -a $IFACE")
        )
        ssh.exec_command(cmd)
        ssh.close()
        return True, f"Speed limit {mbps if mbps > 0 else 'Unlimited'} Mbps diterapkan di VPS Remote."
    except Exception as e:
        return False, str(e)


def get_int_setting_safe(key: str, default: int = 0) -> int:
    try:
        conn = sqlite3.connect("/etc/vpn-bot/vpn_data.db", timeout=15)
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        conn.close()
        return int(row[0]) if row and row[0] not in (None, "") else default
    except Exception:
        return default

def apply_global_speed_limit(mbps: int):
    iface = get_default_iface()
    if not iface:
        return True, "OK"
    if mbps <= 0:
        run_cmd(f"wondershaper -c -a {iface}")
    else:
        run_cmd(f"wondershaper -a {iface} -d {mbps*1024} -u {mbps*1024}")
    return True, "OK"

def provision_remote_vps(srv_row):
    if srv_row["is_local"] == 1:
        run_cmd("systemctl restart dropbear ssh xray vpn-ws-bridge nginx")
        return True, "Komponen & Banner di Server Lokal telah disinkronkan ulang."
    import paramiko
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(srv_row["host"], port=srv_row["ssh_port"], username=srv_row["ssh_user"], password=srv_row["ssh_pass"], timeout=15)
        sftp = ssh.open_sftp()
        if os.path.exists("/etc/issue.net"):
            sftp.put("/etc/issue.net", "/etc/issue.net")
        ssh.exec_command("mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /var/log/xray /etc/xray/certs /etc/dropbear")
        time.sleep(1)
        for fn in ("ws-bridge.py", "proto-daemons.py", "vpn_engine.py"):
            loc_p = f"/etc/vpn-bot/{fn}"
            if os.path.exists(loc_p):
                sftp.put(loc_p, f"/etc/vpn-bot/{fn}")
        if os.path.exists("/root/setup-vpn-full.sh"):
            sftp.put("/root/setup-vpn-full.sh", "/root/setup-vpn-full.sh")
        sftp.close()

        remote_domain = srv_row["host"]
        install_cmd = (
            "nohup bash -c '"
            "export DEBIAN_FRONTEND=noninteractive; "
            "apt-get update -y && apt-get install -y curl wget jq unzip nginx libnginx-mod-stream openssh-server dropbear python3 wondershaper vnstat >/dev/null 2>&1; "
            "sed -i \"/^Banner /d\" /etc/ssh/sshd_config; echo \"Banner /etc/issue.net\" >> /etc/ssh/sshd_config; "
            "systemctl restart ssh || systemctl restart sshd; "
            "chmod +x /etc/vpn-bot/*.py 2>/dev/null; "
            "systemctl restart dropbear xray nginx vpn-ws-bridge 2>/dev/null || true"
            "' >/var/log/vpn-remote-install.log 2>&1 &"
        )
        ssh.exec_command(install_cmd)
        ssh.close()
        return True, f"Komponen & Banner HTML berhasil dipasang ke {srv_row['name']} ({remote_domain})!"
    except Exception as e:
        return False, f"Gagal koneksi SSH: {e}"


def lookup_host_geo(host_or_ip: str):
    import socket, urllib.request
    try:
        ip_addr = socket.gethostbyname(host_or_ip.strip())
    except Exception:
        ip_addr = host_or_ip.strip()
    city, isp = "Singapore", "Cloud Network"
    try:
        req = urllib.request.Request(f"http://ip-api.com/json/{ip_addr}?fields=status,city,isp", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="ignore"))
            if data.get("status") == "success":
                city = data.get("city") or city
                isp = data.get("isp") or isp
                return ip_addr, city, isp
    except Exception:
        pass
    try:
        req2 = urllib.request.Request(f"https://ipinfo.io/{ip_addr}/json", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req2, timeout=4) as resp2:
            data2 = json.loads(resp2.read().decode("utf-8", errors="ignore"))
            city = data2.get("city") or city
            org = data2.get("org") or isp
            isp = re.sub(r"^AS\d+\s+", "", org)
    except Exception:
        pass
    return ip_addr, city, isp

# --- CEK KOMPONEN, INSTALL PENUH & STATISTIK LIVE REMOTE VPS ---
SSH_KEY_FILE = "/etc/vpn-bot/id_ed25519"
SSH_PUB_FILE = "/etc/vpn-bot/id_ed25519.pub"
AUTH_CACHE_FILE = "/etc/vpn-bot/.vps_auth_cache.json"
VOLATILE_PASS_CACHE = {}

def _save_obf_pass(ip_addr: str, pwd: str):
    if not ip_addr or not pwd:
        return
    VOLATILE_PASS_CACHE[ip_addr] = pwd
    try:
        data = {}
        if os.path.exists(AUTH_CACHE_FILE):
            with open(AUTH_CACHE_FILE, "r") as f:
                data = json.load(f)
        data[ip_addr] = base64.b64encode(pwd.encode("utf-8")).decode("utf-8")
        with open(AUTH_CACHE_FILE, "w") as f:
            json.dump(data, f)
        os.chmod(AUTH_CACHE_FILE, 0o600)
    except Exception:
        pass

def _load_obf_pass(ip_addr: str):
    if ip_addr in VOLATILE_PASS_CACHE:
        return VOLATILE_PASS_CACHE[ip_addr]
    try:
        if os.path.exists(AUTH_CACHE_FILE):
            with open(AUTH_CACHE_FILE, "r") as f:
                data = json.load(f)
            b64 = data.get(ip_addr)
            if b64:
                return base64.b64decode(b64.encode("utf-8")).decode("utf-8")
    except Exception:
        pass
    return None

def get_srv_ipv4(srv_row) -> str:
    import socket
    ipv4 = (srv_row["ipv4"] if "ipv4" in srv_row.keys() and srv_row["ipv4"] else "").strip()
    if ipv4:
        return ipv4
    host = (srv_row["host"] or "").strip()
    try:
        return socket.gethostbyname(host)
    except Exception:
        return host

def exec_ssh_sync(ssh, cmd: str, timeout: int = 60):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    out_str = stdout.read().decode("utf-8", errors="ignore").strip()
    err_str = stderr.read().decode("utf-8", errors="ignore").strip()
    return exit_code, out_str, err_str

def connect_remote_ssh(srv_row, temp_pass: str = None, timeout: int = 12):
    import paramiko
    target_ip = get_srv_ipv4(srv_row)
    port = int(srv_row["ssh_port"] or 22)
    user = srv_row["ssh_user"] if "ssh_user" in srv_row.keys() and srv_row["ssh_user"] else "root"

    if temp_pass:
        _save_obf_pass(target_ip, temp_pass)
    pwd = temp_pass or _load_obf_pass(target_ip)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    if not temp_pass and os.path.exists(SSH_KEY_FILE):
        try:
            ssh.connect(target_ip, port=port, username=user, key_filename=SSH_KEY_FILE, timeout=timeout, look_for_keys=False, allow_agent=False)
            return ssh
        except Exception:
            pass

    if pwd:
        ssh.connect(target_ip, port=port, username=user, password=pwd, timeout=timeout, look_for_keys=False, allow_agent=False)
        if os.path.exists(SSH_PUB_FILE):
            try:
                with open(SSH_PUB_FILE, "r") as pf:
                    pub_str = pf.read().strip()
                if pub_str:
                    pair_cmd = (
                        "chmod 700 /root && mkdir -p /root/.ssh && chmod 700 /root/.ssh && "
                        f"grep -qF '{pub_str}' /root/.ssh/authorized_keys 2>/dev/null || echo '{pub_str}' >> /root/.ssh/authorized_keys && "
                        "chmod 600 /root/.ssh/authorized_keys && chown -R root:root /root/.ssh && "
                        "sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null; "
                        "systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true"
                    )
                    exec_ssh_sync(ssh, pair_cmd, timeout=10)
            except Exception:
                pass
        return ssh

    raise RuntimeError("Kunci SSH belum terhubung. Silakan klik tombol '✏️ Edit Login' lalu masukkan Password Root.")

def create_remote_account(srv_row, proto: str, uname: str, secret: str, exp_ssh_date: str):
    safe_username(uname)
    safe_secret(secret)
    ssh = connect_remote_ssh(srv_row, timeout=10)
    if proto == "ssh":
        q = sh_quote
        cmd = f"userdel -f {q(uname)} 2>/dev/null; useradd -e {exp_ssh_date} -s /bin/false -M {q(uname)} && echo {q(uname + ':' + secret)} | chpasswd -c SHA512"
        exec_ssh_sync(ssh, cmd, timeout=10)
    else:
        cmd = f"python3 -c \"import sys; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; e.add_xray_user({sh_quote(proto)},{sh_quote(uname)},{sh_quote(secret)})\""
        exec_ssh_sync(ssh, cmd, timeout=10)
    ssh.close()

def remove_account_from_server(srv_row, proto: str, uname: str):
    safe_username(uname)
    if not srv_row or srv_row["is_local"] == 1:
        if proto == "ssh":
            delete_ssh_user(uname)
        else:
            remove_xray_user(proto, uname)
        return True
    try:
        ssh = connect_remote_ssh(srv_row, timeout=10)
        if proto == "ssh":
            exec_ssh_sync(ssh, f"pkill -9 -u {sh_quote(uname)} 2>/dev/null; userdel -f {sh_quote(uname)} 2>/dev/null", timeout=10)
        else:
            exec_ssh_sync(ssh, f"python3 -c \"import sys; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; e.remove_xray_user({sh_quote(proto)},{sh_quote(uname)})\"", timeout=10)
        ssh.close()
        return True
    except Exception:
        return False

def add_account_to_server(srv_row, proto: str, uname: str, secret: str, exp_ssh_date: str):
    if not srv_row or srv_row["is_local"] == 1:
        if proto == "ssh":
            return create_ssh_user(uname, secret, exp_ssh_date)
        else:
            ok, _ = add_xray_user(proto, uname, secret)
            return ok
    create_remote_account(srv_row, proto, uname, secret, exp_ssh_date)
    return True

def check_remote_vps_components(srv_row, temp_pass: str = None):
    ip_addr = get_srv_ipv4(srv_row)

    if srv_row["is_local"] == 1:
        def loc_act(names):
            for n in names:
                if run_cmd(f"systemctl is-active {n}").stdout.strip() == "active":
                    return True
            return False
        xray_ok = loc_act(["xray"])
        db_ok = loc_act(["dropbear"])
        hap_ok = loc_act(["haproxy", "vpn-ws-bridge"])
        ngx_ok = loc_act(["nginx"])
        ssl_ok = os.path.exists("/etc/xray/certs/fullchain.pem") and os.path.getsize("/etc/xray/certs/fullchain.pem") > 0
        return {
            "ok": True,
            "ip": ip_addr,
            "xray": "🟢 Sudah Ada & Aktif" if xray_ok else "🔴 Belum Ada / Mati",
            "dropbear": "🟢 Sudah Ada & Aktif" if db_ok else "🔴 Belum Ada / Mati",
            "haproxy": "🟢 Sudah Ada & Aktif" if hap_ok else "🔴 Belum Ada / Mati",
            "nginx": "🟢 Sudah Ada / Aktif" if ngx_ok else "🔴 Belum Ada / Mati",
            "ssl": "🟢 Sudah Ada / Aktif" if ssl_ok else "🔴 Belum Ada / Kosong",
        }

    try:
        ssh = connect_remote_ssh(srv_row, temp_pass=temp_pass, timeout=10)
        check_sh = (
            "systemctl is-active --quiet xray 2>/dev/null && xr=active || xr=no; "
            "systemctl is-active --quiet dropbear 2>/dev/null && db=active || db=no; "
            "systemctl is-active --quiet haproxy 2>/dev/null && hp=active || hp=no; "
            "systemctl is-active --quiet vpn-ws-bridge 2>/dev/null && ws=active || ws=no; "
            "systemctl is-active --quiet nginx 2>/dev/null && nx=active || nx=no; "
            "if [ -s /etc/xray/certs/fullchain.pem ] || [ -s /etc/xray/xray.crt ]; then ssl=active; else ssl=no; fi; "
            "echo RESULT:$xr:$db:$hp:$ws:$nx:$ssl"
        )
        _, out_str, _ = exec_ssh_sync(ssh, check_sh, timeout=10)
        ssh.close()

        res_line = "no:no:no:no:no:no"
        for line in out_str.splitlines():
            if "RESULT:" in line:
                res_line = line.split("RESULT:", 1)[1].strip()
                break

        parts = (res_line.split(":") + ["no"] * 6)[:6]
        xr, db, hp, ws, nx, ssl_st = [p.strip() for p in parts]

        return {
            "ok": True,
            "ip": ip_addr,
            "xray": "🟢 Sudah Ada & Aktif" if xr == "active" else "🔴 Belum Ada / Mati",
            "dropbear": "🟢 Sudah Ada & Aktif" if db == "active" else "🔴 Belum Ada / Mati",
            "haproxy": "🟢 Sudah Ada & Aktif" if (hp == "active" or ws == "active") else "🔴 Belum Ada / Mati",
            "nginx": "🟢 Sudah Ada / Aktif" if nx == "active" else "🔴 Belum Ada / Mati",
            "ssl": "🟢 Sudah Ada / Aktif" if ssl_st == "active" else "🔴 Belum Ada / Kosong",
        }
    except Exception as e:
        return {
            "ok": False,
            "ip": ip_addr,
            "error": str(e),
            "xray": "⚪ Tidak Terhubung SSH",
            "dropbear": "⚪ Tidak Terhubung SSH",
            "haproxy": "⚪ Tidak Terhubung SSH",
            "nginx": "⚪ Tidak Terhubung SSH",
            "ssl": "⚪ Tidak Terhubung SSH",
        }

def use_existing_remote_vps(srv_row):
    if srv_row["is_local"] == 1:
        return True, "Server Lokal siap digunakan."
    try:
        ssh = connect_remote_ssh(srv_row, timeout=12)
        exec_ssh_sync(ssh, "mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /var/log/xray", timeout=10)
        sftp = ssh.open_sftp()
        if os.path.exists("/etc/issue.net"):
            sftp.put("/etc/issue.net", "/etc/issue.net")
        if os.path.exists("/etc/vpn-bot/vpn_engine.py"):
            sftp.put("/etc/vpn-bot/vpn_engine.py", "/etc/vpn-bot/vpn_engine.py")
        sftp.close()
        exec_ssh_sync(ssh, "chmod +x /etc/vpn-bot/vpn_engine.py; grep -q '^/bin/false$' /etc/shells || echo '/bin/false' >> /etc/shells", timeout=10)
        ssh.close()
        return True, "Komponen yang sudah ada berhasil ditautkan!"
    except Exception as e:
        return False, f"Gagal terhubung ke SSH: {e}"

def install_full_remote_vps_sync(srv_row):
    if srv_row["is_local"] == 1:
        run_cmd("systemctl restart dropbear ssh xray vpn-ws-bridge nginx")
        return True, "Komponen Server Lokal berhasil di-refresh."
    try:
        host = (srv_row["host"] or "localhost").strip()
        ssh = connect_remote_ssh(srv_row, timeout=15)

        local_arch = run_cmd("uname -m").stdout.strip()
        _, remote_arch, _ = exec_ssh_sync(
            ssh,
            "systemctl stop xray dropbear nginx >/dev/null 2>&1 || true; "
            "mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /var/log/xray /etc/xray/certs /etc/dropbear /var/www/html && uname -m",
            timeout=15
        )
        remote_arch = remote_arch.splitlines()[-1].strip() if remote_arch else ""

        tmp_cert = f"/tmp/cert_{srv_row['id']}.pem"
        tmp_key = f"/tmp/key_{srv_row['id']}.pem"
        run_cmd(
            f"openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -batch "
            f"-keyout {tmp_key} -out {tmp_cert} -subj '/CN={host}' >/dev/null 2>&1"
        )

        tmp_xray_cfg = f"/tmp/xray_cfg_{srv_row['id']}.json"
        base_xray = {
            "log": {"access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info"},
            "inbounds": [
                {"tag": "vmess-ws", "listen": "127.0.0.1", "port": 10001, "protocol": "vmess", "settings": {"clients": []}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}},
                {"tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10002, "protocol": "vmess", "settings": {"clients": []}, "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "vmess"}}},
                {"tag": "vmess-up", "listen": "127.0.0.1", "port": 10003, "protocol": "vmess", "settings": {"clients": []}, "streamSettings": {"network": "httpupgrade", "httpupgradeSettings": {"path": "/upvmess"}}},
                {"tag": "vless-ws", "listen": "127.0.0.1", "port": 10004, "protocol": "vless", "settings": {"clients": [], "decryption": "none"}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/vless"}}},
                {"tag": "vless-grpc", "listen": "127.0.0.1", "port": 10005, "protocol": "vless", "settings": {"clients": [], "decryption": "none"}, "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "vless"}}},
                {"tag": "vless-up", "listen": "127.0.0.1", "port": 10006, "protocol": "vless", "settings": {"clients": [], "decryption": "none"}, "streamSettings": {"network": "httpupgrade", "httpupgradeSettings": {"path": "/upvless"}}},
                {"tag": "trojan-ws", "listen": "127.0.0.1", "port": 10007, "protocol": "trojan", "settings": {"clients": []}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/trojan"}}},
                {"tag": "trojan-grpc", "listen": "127.0.0.1", "port": 10008, "protocol": "trojan", "settings": {"clients": []}, "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "trojan"}}},
                {"tag": "trojan-up", "listen": "127.0.0.1", "port": 10009, "protocol": "trojan", "settings": {"clients": []}, "streamSettings": {"network": "httpupgrade", "httpupgradeSettings": {"path": "/uptrojan"}}},
                {"tag": "ss-ws", "listen": "127.0.0.1", "port": 10010, "protocol": "shadowsocks", "settings": {"method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp"}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/ss-ws"}}},
                {"tag": "ss-grpc", "listen": "127.0.0.1", "port": 10011, "protocol": "shadowsocks", "settings": {"method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp"}, "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "ss-grpc"}}}
            ],
            "outbounds": [
                {"tag": "direct", "protocol": "freedom", "settings": {}},
                {"tag": "blocked", "protocol": "blackhole", "settings": {}}
            ]
        }
        with open(tmp_xray_cfg, "w") as xf:
            json.dump(base_xray, xf, indent=2)

        sftp = ssh.open_sftp()
        upload_map = [
            ("/etc/issue.net", "/etc/issue.net"),
            ("/etc/vpn-bot/ws-bridge.py", "/etc/vpn-bot/ws-bridge.py"),
            ("/etc/vpn-bot/proto-daemons.py", "/etc/vpn-bot/proto-daemons.py"),
            ("/etc/vpn-bot/vpn_engine.py", "/etc/vpn-bot/vpn_engine.py"),
            ("/etc/vpn-bot/remote_installer.sh", "/tmp/remote_install_vpn.sh"),
            (tmp_cert, "/etc/xray/certs/fullchain.pem"),
            (tmp_key, "/etc/xray/certs/privkey.pem"),
            (tmp_xray_cfg, "/etc/xray/config.json"),
        ]
        for src, dst in upload_map:
            if os.path.exists(src):
                sftp.put(src, dst)

        if local_arch and local_arch == remote_arch:
            for bin_src, bin_dst in (
                ("/usr/sbin/dropbear", "/etc/vpn-bot/dropbear.bin"),
                ("/usr/bin/dropbearkey", "/etc/vpn-bot/dropbearkey.bin"),
                ("/usr/local/bin/xray", "/etc/vpn-bot/xray.bin"),
            ):
                if os.path.exists(bin_src):
                    try:
                        sftp.put(bin_src, bin_dst)
                    except Exception:
                        pass
        sftp.close()

        for tf in (tmp_cert, tmp_key, tmp_xray_cfg):
            try:
                os.remove(tf)
            except Exception:
                pass

        _, out_str, err_str = exec_ssh_sync(
            ssh,
            f"chmod +x /tmp/remote_install_vpn.sh && /tmp/remote_install_vpn.sh '{host}'",
            timeout=300
        )
        ssh.close()
        if "INSTALL_OK" in out_str:
            return True, "Seluruh komponen (Xray, Dropbear 2019.78, Multiplexer, Nginx & SSL) berhasil diinstal dan aktif!"
        return False, f"Log Instalasi: {(err_str or out_str)[-250:]}"
    except Exception as e:
        return False, f"Gagal menginstal via SSH: {e}"

def get_remote_dashboard_stats(srv_row):
    ip_addr = get_srv_ipv4(srv_row)
    try:
        ssh = connect_remote_ssh(srv_row, timeout=5)
        remote_py = (
            "python3 -c '"
            "import time, shutil, json, subprocess\n"
            "def r_cmd(c): return subprocess.run(c, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout.strip()\n"
            "iface = r_cmd(\"ip route get 8.8.8.8 2>/dev/null | awk \\x27{print $5; exit}\\x27\") or \"eth0\"\n"
            "def cpu():\n"
            "  p = [float(x) for x in open(\"/proc/stat\").readline().split()[1:]]\n"
            "  return p[3] + (p[4] if len(p)>4 else 0), sum(p)\n"
            "def net():\n"
            "  return int(open(f\"/sys/class/net/{iface}/statistics/rx_bytes\").read()), int(open(f\"/sys/class/net/{iface}/statistics/tx_bytes\").read())\n"
            "i1, t1 = cpu(); rx1, tx1 = net(); time.sleep(0.15); i2, t2 = cpu(); rx2, tx2 = net()\n"
            "c_pct = max(0.0, min(100.0, (1.0 - (i2-i1)/max(1.0, t2-t1))*100.0))\n"
            "in_m = max(0.0, ((rx2-rx1)*8.0)/0.15/1e6); out_m = max(0.0, ((tx2-tx1)*8.0)/0.15/1e6)\n"
            "m = r_cmd(\"free -m | awk \\x27/^Mem:/ {print $3, $2}\\x27\").split()\n"
            "ru, rt = int(m[0]), max(1, int(m[1]))\n"
            "du = shutil.disk_usage(\"/\")\n"
            "day_b, mth_b = rx2+tx2, rx2+tx2\n"
            "try:\n"
            "  vj = json.loads(r_cmd(f\"vnstat -i {iface} --json\") or r_cmd(\"vnstat --json\"))\n"
            "  tr = vj[\"interfaces\"][0][\"traffic\"]\n"
            "  d_l = tr.get(\"day\", tr.get(\"days\", [])); m_l = tr.get(\"month\", tr.get(\"months\", []))\n"
            "  if d_l: day_b = int(d_l[-1].get(\"rx\",0)) + int(d_l[-1].get(\"tx\",0))\n"
            "  if m_l: mth_b = int(m_l[-1].get(\"rx\",0)) + int(m_l[-1].get(\"tx\",0))\n"
            "except Exception: pass\n"
            "print(json.dumps({\"cpu\":f\"{c_pct:.1f}%\",\"ram\":f\"{ru} MB / {rt} MB ({ru/rt*100:.1f}%)\",\"disk\":f\"{du.used/(1024**3):.0f} GB / {max(1,du.total/(1024**3)):.0f} GB ({du.used/du.total*100:.1f}%)\",\"in_m\":f\"{in_m:.2f} Mbps\",\"out_m\":f\"{out_m:.2f} Mbps\",\"day_b\":day_b,\"mth_b\":mth_b}))"
            "'"
        )
        _, raw_out, _ = exec_ssh_sync(ssh, remote_py, timeout=8)
        ssh.close()
        d = json.loads(raw_out.splitlines()[-1])
        day_b = int(d.get("day_b", 0))
        mth_b = int(d.get("mth_b", 0))
        return {
            "online": True,
            "ip": ip_addr,
            "cpu_pct": d["cpu"],
            "ram_str": d["ram"],
            "disk_str": d["disk"],
            "bw_gb_str": f"{day_b / (1024**3):.2f} GB",
            "in_mbps": d["in_m"],
            "out_mbps": d["out_m"],
            "vnstat_day": format_data_size(day_b),
            "vnstat_mth": format_data_size(mth_b),
        }
    except Exception:
        return {"online": False, "ip": ip_addr}


# --- FITUR V11: CHANGE DOMAIN, PRO BUG SCANNER & AUTO-HEAL ---
def change_server_domain(srv_row, new_domain: str):
    new_domain = new_domain.strip().replace("http://", "").replace("https://", "").split("/")[0]
    try:
        safe_domain(new_domain)
    except ValueError as e:
        return False, str(e)
    if not new_domain:
        return False, "Domain baru tidak boleh kosong."

    if srv_row["is_local"] == 1:
        try:
            # 1. Update /etc/vpn-bot/config.env
            if os.path.exists("/etc/vpn-bot/config.env"):
                with open("/etc/vpn-bot/config.env", "r") as f:
                    lines = f.readlines()
                with open("/etc/vpn-bot/config.env", "w") as f:
                    for line in lines:
                        if line.startswith("DOMAIN="):
                            f.write(f'DOMAIN="{new_domain}"\n')
                        else:
                            f.write(line)

            # 2. Update /etc/nginx/nginx.conf
            if os.path.exists("/etc/nginx/nginx.conf"):
                with open("/etc/nginx/nginx.conf", "r") as f:
                    ngx = f.read()
                ngx = re.sub(r"server_name\s+[^;]+;", f"server_name {new_domain} _;", ngx)
                with open("/etc/nginx/nginx.conf", "w") as f:
                    f.write(ngx)

            # 3. Buat Sertifikat SSL baru (Let's Encrypt atau Fallback X.509)
            run_cmd("mkdir -p /etc/xray/certs /var/www/html")
            cert_ok = False
            res_le = run_cmd(f"certbot certonly --webroot -w /var/www/html -d {new_domain} --non-interactive --agree-tos -m admin@{new_domain} --force-renewal")
            if res_le.returncode == 0 and os.path.exists(f"/etc/letsencrypt/live/{new_domain}/fullchain.pem"):
                run_cmd(f"cp -f /etc/letsencrypt/live/{new_domain}/fullchain.pem /etc/xray/certs/fullchain.pem")
                run_cmd(f"cp -f /etc/letsencrypt/live/{new_domain}/privkey.pem /etc/xray/certs/privkey.pem")
                cert_ok = True
            if not cert_ok:
                run_cmd(
                    f"openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -batch "
                    f"-keyout /etc/xray/certs/privkey.pem -out /etc/xray/certs/fullchain.pem -subj '/CN={new_domain}'"
                )
            run_cmd("chmod 644 /etc/xray/certs/fullchain.pem /etc/xray/certs/privkey.pem")
            run_cmd("systemctl restart nginx xray")
            return True, f"Domain Server Utama berhasil diubah ke {new_domain} (Nginx & SSL diperbarui)!"
        except Exception as e:
            return False, f"Gagal mengubah domain lokal: {e}"
    else:
        try:
            ssh = connect_remote_ssh(srv_row, timeout=12)
            tmp_cert = f"/tmp/cert_chg_{srv_row['id']}.pem"
            tmp_key = f"/tmp/key_chg_{srv_row['id']}.pem"
            run_cmd(
                f"openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -batch "
                f"-keyout {tmp_key} -out {tmp_cert} -subj '/CN={new_domain}'"
            )
            sftp = ssh.open_sftp()
            if os.path.exists(tmp_cert):
                sftp.put(tmp_cert, "/etc/xray/certs/fullchain.pem")
            if os.path.exists(tmp_key):
                sftp.put(tmp_key, "/etc/xray/certs/privkey.pem")
            sftp.close()
            for tf in (tmp_cert, tmp_key):
                try:
                    os.remove(tf)
                except Exception:
                    pass
            cmd = (
                f"sed -i 's/server_name .* _;/server_name {new_domain} _;/g' /etc/nginx/nginx.conf 2>/dev/null || true; "
                f"certbot certonly --webroot -w /var/www/html -d {new_domain} --non-interactive --agree-tos -m admin@{new_domain} >/dev/null 2>&1 && "
                f"cp -f /etc/letsencrypt/live/{new_domain}/fullchain.pem /etc/xray/certs/fullchain.pem && "
                f"cp -f /etc/letsencrypt/live/{new_domain}/privkey.pem /etc/xray/certs/privkey.pem || true; "
                "chmod 644 /etc/xray/certs/fullchain.pem /etc/xray/certs/privkey.pem; "
                "systemctl restart nginx xray"
            )
            exec_ssh_sync(ssh, cmd, timeout=25)
            ssh.close()
            return True, f"Domain VPS Remote ({srv_row['name']}) berhasil diubah ke {new_domain}!"
        except Exception as e:
            return False, f"Gagal mengubah domain di VPS Remote: {e}"

def scan_single_bug_target(target_raw: str, vpn_domain: str) -> dict:
    import socket, ssl, urllib.request
    bug = target_raw.strip().replace("http://", "").replace("https://", "").split("/")[0].split(":")[0]
    res = {
        "bug": bug,
        "ips_str": "-",
        "asn_str": "-",
        "ping_ms": "-",
        "server_hdr": "-",
        "cdn_status": "⚪ Direct / Non-CDN",
        "ssl_info": "-",
        "sans": [],
        "http_80": "🔴 Timeout / Closed",
        "https_443": "🔴 Timeout / Closed",
        "ws_wildcard": "🔴 SSLError",
        "ws_direct_cdn": "🔴 Gagal / Ditolak",
        "is_cf": False,
        "cdn_101_ok": False,
        "wildcard_101_ok": False,
        "ssl_ok": False,
    }
    if not bug:
        return res

    # 1. Resolve semua IPv4 Address
    ip_list = []
    try:
        infos = socket.getaddrinfo(bug, None, socket.AF_INET, socket.SOCK_STREAM)
        for info in infos:
            ip = info[4][0]
            if ip not in ip_list:
                ip_list.append(ip)
            if len(ip_list) >= 4:
                break
    except Exception:
        pass

    if not ip_list:
        return res

    first_ip = ip_list[0]
    res["ips_str"] = ", ".join(ip_list)

    # 2. Ukur TCP Ping (ms)
    for p in (443, 80):
        t0 = time.time()
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.5)
        try:
            s.connect((first_ip, p))
            dt_ms = max(1, int(round((time.time() - t0) * 1000.0)))
            res["ping_ms"] = f"{dt_ms} ms"
            s.close()
            break
        except Exception:
            s.close()

    # 3. Lookup ASN & Organization
    try:
        req = urllib.request.Request(
            f"http://ip-api.com/json/{first_ip}?fields=status,isp,org,as",
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            jd = json.loads(resp.read().decode("utf-8", errors="ignore"))
            if jd.get("status") == "success":
                as_raw = jd.get("as") or "-"
                org_raw = jd.get("org") or jd.get("isp") or "-"
                res["asn_str"] = f"{as_raw} ({org_raw})"
                if "cloudflare" in (as_raw + " " + org_raw).lower():
                    res["is_cf"] = True
    except Exception:
        pass

    cf_ray = ""

    # 4. Tes HTTP Biasa (Port 80) ke Bug
    try:
        s80 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s80.settimeout(3.0)
        s80.connect((first_ip, 80))
        req80 = (
            f"GET / HTTP/1.1\r\n"
            f"Host: {bug}\r\n"
            f"User-Agent: Mozilla/5.0\r\n"
            f"Connection: close\r\n\r\n"
        ).encode("latin-1")
        s80.sendall(req80)
        raw80 = s80.recv(2048).decode("latin-1", errors="ignore")
        s80.close()
        if raw80:
            lines80 = raw80.splitlines()
            st_line = lines80[0].replace("HTTP/1.1 ", "").replace("HTTP/1.0 ", "").strip()
            res["http_80"] = f"🟢 <code>{html.escape(st_line[:35])}</code>"
            for ln in lines80[1:]:
                low = ln.lower()
                if low.startswith("server:") and res["server_hdr"] == "-":
                    res["server_hdr"] = ln.split(":", 1)[1].strip()
                elif low.startswith("cf-ray:") and not cf_ray:
                    cf_ray = ln.split(":", 1)[1].strip()
    except Exception as e:
        res["http_80"] = f"🔴 <code>{html.escape(type(e).__name__)}</code>"

    # 5. Cek Info SSL/TLS (ALPN h2/http1.1 + SANs) & Tes HTTPS Port 443
    try:
        ctx_alpn = ssl.create_default_context()
        ctx_alpn.check_hostname = False
        ctx_alpn.verify_mode = ssl.CERT_NONE
        ctx_alpn.set_alpn_protocols(["h2", "http/1.1"])

        s443 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s443.settimeout(3.5)
        s443.connect((first_ip, 443))
        ss443 = ctx_alpn.wrap_socket(s443, server_hostname=bug)
        res["ssl_ok"] = True
        tls_ver = ss443.version() or "TLSv1.3"
        alpn_proto = ss443.selected_alpn_protocol() or "http/1.1"
        res["ssl_info"] = f"{tls_ver} | ALPN: {alpn_proto}"

        der_cert = ss443.getpeercert(binary_form=True)
        if der_cert:
            pem_str = ssl.DER_cert_to_PEM_cert(der_cert)
            p_ossl = subprocess.Popen(
                ["openssl", "x509", "-noout", "-ext", "subjectAltName"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            out_san, _ = p_ossl.communicate(pem_str, timeout=3)
            found_sans = re.findall(r"DNS:([a-zA-Z0-9\*\-\._]+)", out_san)
            seen = []
            for sn in found_sans:
                if sn not in seen:
                    seen.append(sn)
                if len(seen) >= 6:
                    break
            res["sans"] = seen
        ss443.close()
    except Exception:
        pass

    # Ambil HTTP Status Code di Port 443 menggunakan ALPN http/1.1
    try:
        ctx_h1 = ssl.create_default_context()
        ctx_h1.check_hostname = False
        ctx_h1.verify_mode = ssl.CERT_NONE
        ctx_h1.set_alpn_protocols(["http/1.1"])

        s443_h1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s443_h1.settimeout(3.5)
        s443_h1.connect((first_ip, 443))
        ss443_h1 = ctx_h1.wrap_socket(s443_h1, server_hostname=bug)
        req443 = (
            f"GET / HTTP/1.1\r\n"
            f"Host: {bug}\r\n"
            f"User-Agent: Mozilla/5.0\r\n"
            f"Connection: close\r\n\r\n"
        ).encode("latin-1")
        ss443_h1.sendall(req443)
        raw443 = ss443_h1.recv(2048).decode("latin-1", errors="ignore")
        ss443_h1.close()
        if raw443:
            lines443 = raw443.splitlines()
            st443 = lines443[0].replace("HTTP/1.1 ", "").replace("HTTP/1.0 ", "").strip()
            res["https_443"] = f"🟢 <code>{html.escape(st443[:35])}</code>"
            for ln in lines443[1:]:
                low = ln.lower()
                if low.startswith("server:"):
                    res["server_hdr"] = ln.split(":", 1)[1].strip()
                elif low.startswith("cf-ray:"):
                    cf_ray = ln.split(":", 1)[1].strip()
    except Exception as e:
        res["https_443"] = f"🔴 <code>{html.escape(type(e).__name__)}</code>"

    if "cloudflare" in res["server_hdr"].lower() or cf_ray:
        res["is_cf"] = True

    if res["is_cf"]:
        ray_info = f" (CF-Ray: {cf_ray})" if cf_ray else ""
        res["cdn_status"] = f"✅ <code>Cloudflare{html.escape(ray_info)}</code>"
    elif res["server_hdr"] != "-":
        res["cdn_status"] = f"🟢 <code>{html.escape(res['server_hdr'])}</code>"

    # 6. Tes WS Wildcard (SNI = bug.vpn_domain ke IP Bug Port 443)
    try:
        ctx_wc = ssl.create_default_context()
        ctx_wc.check_hostname = False
        ctx_wc.verify_mode = ssl.CERT_NONE
        s_wc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s_wc.settimeout(3.0)
        s_wc.connect((first_ip, 443))
        wc_host = f"{bug}.{vpn_domain}"
        ss_wc = ctx_wc.wrap_socket(s_wc, server_hostname=wc_host)
        ws_req = (
            f"GET / HTTP/1.1\r\n"
            f"Host: {wc_host}\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n\r\n"
        ).encode("latin-1")
        ss_wc.sendall(ws_req)
        r_wc = ss_wc.recv(1024).decode("latin-1", errors="ignore")
        ss_wc.close()
        fl_wc = r_wc.splitlines()[0].replace("HTTP/1.1 ", "").strip() if r_wc else ""
        if "101" in fl_wc:
            res["ws_wildcard"] = "🔥 <code>101 Switching Protocols (TEMBUS!)</code>"
            res["wildcard_101_ok"] = True
        elif fl_wc:
            res["ws_wildcard"] = f"🟡 <code>{html.escape(fl_wc[:30])}</code>"
        else:
            res["ws_wildcard"] = "🔴 <code>Empty Response</code>"
    except ssl.SSLError:
        res["ws_wildcard"] = "🔴 <code>SSLError</code>"
    except Exception as e:
        res["ws_wildcard"] = f"🔴 <code>{html.escape(type(e).__name__)}</code>"

    # 7. Tes WS Direct CDN (Kirim Payload WS Host: vpn_domain ke IP Bug & Simulasi Server)
    cdn_ws_resp = ""
    for test_port, use_ssl in ((80, False), (443, True)):
        try:
            s_cdn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s_cdn.settimeout(3.0)
            s_cdn.connect((first_ip, test_port))
            if use_ssl:
                ctx_c = ssl.create_default_context()
                ctx_c.check_hostname = False
                ctx_c.verify_mode = ssl.CERT_NONE
                s_cdn = ctx_c.wrap_socket(s_cdn, server_hostname=vpn_domain)
            p_cdn = (
                f"GET / HTTP/1.1\r\n"
                f"Host: {vpn_domain}\r\n"
                f"User-Agent: Mozilla/5.0\r\n"
                f"Upgrade: websocket\r\n"
                f"Connection: Upgrade\r\n\r\n"
            ).encode("latin-1")
            s_cdn.sendall(p_cdn)
            r_cdn = s_cdn.recv(1024).decode("latin-1", errors="ignore")
            s_cdn.close()
            if r_cdn:
                fl_c = r_cdn.splitlines()[0].replace("HTTP/1.1 ", "").strip()
                if "101" in fl_c:
                    cdn_ws_resp = "101 Switching Protocols"
                    res["cdn_101_ok"] = True
                    break
                elif not cdn_ws_resp:
                    cdn_ws_resp = fl_c[:30]
        except Exception:
            pass

    # Jika bug berada di jaringan Cloudflare (atau merespons HTTP/HTTPS aktif) dan server lokal siap menerima WS Upgrade
    if not res["cdn_101_ok"] and (res["is_cf"] or res["ssl_ok"]):
        try:
            s_loc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s_loc.settimeout(2.5)
            s_loc.connect(("127.0.0.1", 80))
            p_loc = (
                f"GET / HTTP/1.1\r\n"
                f"Host: {vpn_domain}\r\n"
                f"Host: {bug}\r\n"
                f"Upgrade: websocket\r\n"
                f"Connection: Upgrade\r\n\r\n"
            ).encode("latin-1")
            s_loc.sendall(p_loc)
            r_loc = s_loc.recv(1024).decode("latin-1", errors="ignore")
            s_loc.close()
            if "101" in r_loc and res["is_cf"]:
                cdn_ws_resp = "101 Switching Protocols"
                res["cdn_101_ok"] = True
        except Exception:
            pass

    if res["cdn_101_ok"]:
        res["ws_direct_cdn"] = "🔥 <code>101 Switching Protocols (TEMBUS!)</code>"
    elif cdn_ws_resp:
        res["ws_direct_cdn"] = f"🟡 <code>{html.escape(cdn_ws_resp)}</code>"
    else:
        res["ws_direct_cdn"] = "🔴 <code>Gagal / Closed</code>"

    return res

def run_auto_heal_check(servers_rows) -> list:
    """
    Memeriksa seluruh service inti di VPS Utama & VPS Tambahan.
    Jika ada service mati, otomatis me-restartnya dan mengembalikan daftar laporan kejadian.
    """
    events = []
    local_services = [
        ("xray", "Xray-Core"),
        ("dropbear", "Dropbear SSH"),
        ("vpn-ws-bridge", "WS-Bridge Multiplexer"),
        ("nginx", "Nginx Stream/Web"),
    ]
    for unit, label in local_services:
        st = run_cmd(f"systemctl is-active {unit}").stdout.strip()
        if st != "active":
            run_cmd(f"systemctl restart {unit}")
            time.sleep(1)
            st_after = run_cmd(f"systemctl is-active {unit}").stdout.strip()
            status_str = "🟢 Berhasil Dihidupkan Kembali" if st_after == "active" else "🔴 Gagal Restart (Perlu Cek Manual)"
            events.append(f"🖥 <b>Server Utama (Lokal)</b>: Service <b>{label}</b> terdeteksi mati (<code>{st}</code>) -> Auto-Heal: {status_str}")

    for srv in servers_rows:
        if srv["is_local"] == 1:
            continue
        try:
            ssh = connect_remote_ssh(srv, timeout=8)
            heal_cmd = (
                "healed=''; "
                "for u in xray dropbear vpn-ws-bridge nginx; do "
                "  if ! systemctl is-active --quiet $u 2>/dev/null; then "
                "    systemctl restart $u 2>/dev/null || true; "
                "    sleep 1; "
                "    if systemctl is-active --quiet $u 2>/dev/null; then healed=\"${healed}${u}:OK,\"; else healed=\"${healed}${u}:FAIL,\"; fi; "
                "  fi; "
                "done; "
                "echo \"HEAL_RES:${healed}\""
            )
            _, out_str, _ = exec_ssh_sync(ssh, heal_cmd, timeout=15)
            ssh.close()
            for line in out_str.splitlines():
                if line.startswith("HEAL_RES:"):
                    val = line.split("HEAL_RES:", 1)[1].strip().strip(",")
                    if val:
                        events.append(f"🌐 <b>{html.escape(srv['name'])} ({html.escape(srv['host'])})</b>: Auto-Heal dijalankan -> <code>{html.escape(val)}</code>")
        except Exception as e:
            events.append(f"⚠️ <b>{html.escape(srv['name'])} ({html.escape(srv['host'])})</b>: Server tidak merespons ping SSH (<code>{html.escape(str(e)[:60])}</code>)")
    return events


# --- OVERRIDE FLEKSIBEL LOCK & UNLOCK SSH / XRAY (LOKAL & REMOTE) + INSTANT PID KICK ---
def kill_active_ssh_pids(username: str):
    """Mematikan paksa seluruh PID Dropbear & OpenSSH milik username."""
    kill_sh = (
        f"pids=$(grep -F \"Password auth succeeded for '{username}'\" /var/log/dropbear.log 2>/dev/null "
        "| grep -oE '\\[[0-9]+\\]' | tr -d '[]' | sort -u); "
        "for pid in $pids; do "
        "  if [ -d \"/proc/$pid\" ] && grep -qi 'dropbear' \"/proc/$pid/comm\" 2>/dev/null; then "
        "    kill -9 \"$pid\" 2>/dev/null || true; "
        "  fi; "
        "done; "
        f"pkill -9 -f \"sshd: {username}\" 2>/dev/null || true; "
        f"pkill -9 -u \"{username}\" 2>/dev/null || true"
    )
    run_cmd(kill_sh)

def _lookup_db_secret(username: str) -> str:
    try:
        import sqlite3
        conn = sqlite3.connect("/etc/vpn-bot/vpn_data.db", timeout=15)
        row = conn.execute("SELECT secret FROM accounts WHERE username=?", (username,)).fetchone()
        conn.close()
        return row[0] if row and row[0] else ""
    except Exception:
        return ""



def delete_ssh_user(username: str):
    safe_username(username)
    kill_active_ssh_pids(username)
    run_argv(["userdel", "-f", username])
    return True


def get_remote_active_sessions(srv_row) -> dict:
    if not srv_row or srv_row["is_local"] == 1:
        return get_active_sessions()
    try:
        ssh = connect_remote_ssh(srv_row, timeout=6)
        cmd = "python3 -c \"import sys, json; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; print('SESS_JSON:' + json.dumps(e.get_active_sessions()))\""
        _, out_str, _ = exec_ssh_sync(ssh, cmd, timeout=8)
        ssh.close()
        for line in out_str.splitlines():
            if line.startswith("SESS_JSON:"):
                return json.loads(line.split("SESS_JSON:", 1)[1].strip())
    except Exception:
        pass
    return {"ssh": {}, "xray": {}}


# --- AUTO-SYNC PASSWORD & UUID OTOMATIS SAAT LOCK / UNLOCK (LOKAL & REMOTE) ---





# --- FITUR V14 & V15: KOLEKTOR DATA LOGIN DETAIL, PEMAKAIAN KUOTA USER & TIMESTAMP IP ---
USER_BW_STORE = "/var/log/vpn-user-bw.json"
PORT_BW_FILE = "/var/log/vpn-port-bw.json"





# --- DETEKTOR MULTI-LOGIN PRESISI TINGGI (MURNI REAL-IP UNIK, BEBAS FALSE-LOCK 1 HP) ---
def get_active_sessions() -> dict:
    """
    Melacak daftar IP publik unik yang sedang aktif per akun untuk SSH (Dropbear/OpenSSH)
    dan Xray (VMess/VLESS/Trojan).
    1 HP yang membuka banyak PID/Socket dari IP yang sama dihitung 1 IP (tidak pernah false-lock).
    """
    ssh_sessions = {}
    xray_sessions = {}
    now = int(time.time())

    port_to_ip = {}
    if os.path.exists("/var/log/vpn-ws-map.log"):
        try:
            with open("/var/log/vpn-ws-map.log", "r", errors="ignore") as f:
                lines = f.readlines()[-5000:]
            for ln in lines:
                parts = ln.strip().split("|")
                if len(parts) >= 3 and parts[1].isdigit():
                    port_to_ip[int(parts[1])] = parts[2].strip()
        except Exception:
            pass

    est_ssh_lports = set()
    est_xray_lports = set()
    ss_out = run_cmd("ss -tn state established 2>/dev/null").stdout
    for ln in ss_out.splitlines():
        cols = ln.split()
        if len(cols) >= 4:
            loc_col, peer_col = cols[-2], cols[-1]
            if ":90" in loc_col and "127.0.0.1:" in peer_col:
                try:
                    est_ssh_lports.add(int(peer_col.rsplit(":", 1)[1]))
                except Exception:
                    pass
            for xp in ("10001", "10002", "10003", "10004", "10005", "10006", "10007", "10008", "10009", "10010"):
                if f":{xp}" in loc_col and "127.0.0.1:" in peer_col:
                    try:
                        est_xray_lports.add(int(peer_col.rsplit(":", 1)[1]))
                    except Exception:
                        pass

    alive_db_pids = set()
    for pid_str in os.listdir("/proc"):
        if pid_str.isdigit():
            try:
                with open(f"/proc/{pid_str}/comm", "r") as cf:
                    if "dropbear" in cf.read().lower():
                        alive_db_pids.add(int(pid_str))
            except Exception:
                pass

    if os.path.exists("/var/log/dropbear.log") and alive_db_pids:
        try:
            with open("/var/log/dropbear.log", "r", errors="ignore") as f:
                db_lines = f.readlines()[-4000:]
            pid_auth_map = {}
            exited_pids = set()
            for ln in db_lines:
                m_pid = re.search(r"\[(\d+)\]", ln)
                if not m_pid:
                    continue
                pid_num = int(m_pid.group(1))
                if "Exit (" in ln or "Exit before auth" in ln:
                    exited_pids.add(pid_num)
                    pid_auth_map.pop(pid_num, None)
                    continue
                m_auth = re.search(r"Password auth succeeded for '([^']+)' from ([0-9a-fA-F\.\:]+):(\d+)", ln)
                if m_auth:
                    pid_auth_map[pid_num] = (m_auth.group(1).strip(), m_auth.group(2).strip(), int(m_auth.group(3)))

            for pid_num, (u_name, src_ip, src_port) in pid_auth_map.items():
                if pid_num not in alive_db_pids or pid_num in exited_pids:
                    continue
                if src_ip in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
                    if est_ssh_lports and src_port not in est_ssh_lports:
                        continue
                    real_ip = port_to_ip.get(src_port, "").split(":")[0].strip()
                    if not real_ip or real_ip.startswith("127."):
                        continue
                else:
                    real_ip = src_ip
                u_list = ssh_sessions.setdefault(u_name, [])
                if real_ip not in u_list:
                    u_list.append(real_ip)
        except Exception:
            pass

    if os.path.exists("/var/log/xray/access.log"):
        try:
            with open("/var/log/xray/access.log", "r", errors="ignore") as f:
                x_lines = f.readlines()[-4000:]
            cutoff_ts = now - 75
            for ln in x_lines:
                if "email:" not in ln or "accepted" not in ln:
                    continue
                m_dt = re.match(r"^(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})", ln)
                is_recent = True
                if m_dt:
                    try:
                        l_ts = int(calendar.timegm(time.strptime(m_dt.group(1), "%Y/%m/%d %H:%M:%S")))
                        if l_ts < cutoff_ts:
                            is_recent = False
                    except Exception:
                        pass

                m_src = re.search(r"from\s+(?:tcp:)?([0-9a-fA-F\.\:]+):(\d+)\s+accepted", ln)
                m_em = re.search(r"email:\s*([^\s]+)", ln)
                if not m_src or not m_em:
                    continue
                src_ip = m_src.group(1).strip()
                src_port = int(m_src.group(2))
                raw_email = m_em.group(1).strip()
                u_name = raw_email.split("|")[-1]
                for pfx_tag in ("vmess-", "vless-", "trojan-", "ss-"):
                    if u_name.startswith(pfx_tag):
                        u_name = u_name[len(pfx_tag):]
                        break

                if src_ip in ("127.0.0.1", "::1"):
                    if (src_port in est_xray_lports) or is_recent:
                        rip = port_to_ip.get(src_port, "").split(":")[0].strip()
                        if not rip or rip.startswith("127."):
                            continue
                        u_list = xray_sessions.setdefault(u_name, [])
                        if rip not in u_list:
                            u_list.append(rip)
                else:
                    if is_recent and not src_ip.startswith("127."):
                        u_list = xray_sessions.setdefault(u_name, [])
                        if src_ip not in u_list:
                            u_list.append(src_ip)
        except Exception:
            pass

    return {"ssh": ssh_sessions, "xray": xray_sessions}

# --- AUTO-SYNC PASSWORD & UUID OTOMATIS SAAT LOCK / UNLOCK (LOKAL & REMOTE) ---
def _get_acc_info_from_db(username: str):
    try:
        import sqlite3
        conn = sqlite3.connect("/etc/vpn-bot/vpn_data.db", timeout=15)
        conn.row_factory = sqlite3.Row
        acc = conn.execute("SELECT * FROM accounts WHERE username=?", (username,)).fetchone()
        if not acc:
            conn.close()
            return None, None
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone()
        conn.close()
        return acc, srv
    except Exception:
        return None, None

def sync_ssh_password_local(username: str, password: str):
    safe_username(username)
    safe_secret(password)
    cmd = (
        f"id -u '{username}' >/dev/null 2>&1 || useradd -s /bin/false -M '{username}' 2>/dev/null || true; "
        f"sed -i 's/^{username}:!\\+/{username}:/' /etc/shadow 2>/dev/null || true; "
        f"usermod -U '{username}' 2>/dev/null || true; "
        f"passwd -u '{username}' 2>/dev/null || true; "
        f"chage -E -1 '{username}' 2>/dev/null || true"
    )
    run_cmd(cmd)
    # Password dikirim via stdin chpasswd (bukan echo) agar tak bocor ke shell
    p = subprocess.Popen(["chpasswd", "-c", "SHA512"], stdin=subprocess.PIPE, text=True)
    p.communicate(f"{username}:{password}\n")

def lock_ssh_user(username: str, lock: bool = True, secret: str = None):
    acc, srv = _get_acc_info_from_db(username)
    pwd = secret or (acc["secret"] if acc else "")
    if srv and srv["is_local"] == 0:
        return set_remote_or_local_lock(srv, "ssh", username, pwd, lock=lock)

    if lock:
        safe_username(username)
        p = subprocess.Popen(["chpasswd", "-c", "SHA512"], stdin=subprocess.PIPE, text=True)
        p.communicate(f"{username}:{LOCKED_PASSWORD}\n")
        kill_active_ssh_pids(username)
    else:
        if pwd:
            sync_ssh_password_local(username, pwd)
    return True

def unlock_ssh_user(username: str, secret: str = None):
    return lock_ssh_user(username, lock=False, secret=secret)

def set_remote_or_local_lock(srv_row, proto: str, uname: str, secret: str = None, lock: bool = True):
    safe_username(uname)
    acc, db_srv = _get_acc_info_from_db(uname)
    target_srv = srv_row or db_srv
    pwd = secret or (acc["secret"] if acc else "")

    if not target_srv or target_srv["is_local"] == 1:
        if proto == "ssh":
            safe_username(uname)
            if lock:
                p = subprocess.Popen(["chpasswd", "-c", "SHA512"], stdin=subprocess.PIPE, text=True)
                p.communicate(f"{uname}:{LOCKED_PASSWORD}\n")
                kill_active_ssh_pids(uname)
            else:
                sync_ssh_password_local(uname, pwd)
        else:
            if lock:
                remove_xray_user(proto, uname)
            else:
                add_xray_user(proto, uname, pwd)
                run_cmd(f"sed -i '/{uname}/d' /var/log/xray/access.log 2>/dev/null || true")
        return True

    try:
        ssh = connect_remote_ssh(target_srv, timeout=12)
        if proto == "ssh":
            safe_username(uname)
            if lock:
                remote_lock_cmd = (
                    f"echo {sh_quote(uname + ':' + LOCKED_PASSWORD)} | chpasswd -c SHA512 2>/dev/null || usermod -L {sh_quote(uname)} 2>/dev/null || true; "
                    f"pids=$(grep -F \"Password auth succeeded for {sh_quote(uname)}\" /var/log/dropbear.log 2>/dev/null "
                    "| grep -oE '\\[[0-9]+\\]' | tr -d '[]' | sort -u); "
                    "for pid in $pids; do "
                    "  if [ -d \"/proc/$pid\" ] && grep -qi 'dropbear' \"/proc/$pid/comm\" 2>/dev/null; then "
                    "    kill -9 \"$pid\" 2>/dev/null || true; "
                    "  fi; "
                    "done; "
                    f"pkill -9 -f \"sshd: {uname}\" 2>/dev/null || true; "
                    f"pkill -9 -u {sh_quote(uname)} 2>/dev/null || true"
                )
                exec_ssh_sync(ssh, remote_lock_cmd, timeout=10)
            else:
                safe_secret(pwd)
                remote_sync_cmd = (
                    f"id -u {sh_quote(uname)} >/dev/null 2>&1 || useradd -s /bin/false -M {sh_quote(uname)} 2>/dev/null || true; "
                    f"sed -i 's/^{uname}:!\\+/{uname}:/' /etc/shadow 2>/dev/null || true; "
                    f"usermod -U {sh_quote(uname)} 2>/dev/null || true; "
                    f"passwd -u {sh_quote(uname)} 2>/dev/null || true; "
                    f"chage -E -1 {sh_quote(uname)} 2>/dev/null || true"
                )
                exec_ssh_sync(ssh, remote_sync_cmd, timeout=10)
                p = subprocess.Popen(["chpasswd", "-c", "SHA512"], stdin=subprocess.PIPE, text=True)
                p.communicate(f"{uname}:{pwd}\n")
        else:
            if lock:
                exec_ssh_sync(ssh, f"python3 -c \"import sys; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; e.remove_xray_user({sh_quote(proto)},{sh_quote(uname)})\"", timeout=10)
            else:
                safe_secret(pwd)
                exec_ssh_sync(
                    ssh,
                    f"sed -i '/{uname}/d' /var/log/xray/access.log 2>/dev/null || true; "
                    f"python3 -c \"import sys; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; e.add_xray_user({sh_quote(proto)},{sh_quote(uname)},{sh_quote(pwd)})\"",
                    timeout=10
                )
        ssh.close()
        return True
    except Exception:
        return False

# --- FITUR V14 & V15: KOLEKTOR DATA LOGIN DETAIL, PEMAKAIAN KUOTA USER & TIMESTAMP IP ---
USER_BW_STORE = "/var/log/vpn-user-bw.json"
PORT_BW_FILE = "/var/log/vpn-port-bw.json"

def format_user_bw_usage(num_bytes: int) -> str:
    if num_bytes <= 0:
        return "1MB"
    gb_val = num_bytes / (1024 ** 3)
    if gb_val >= 1.0:
        return f"{gb_val:.2f}GB"
    mb_val = num_bytes / (1024 ** 2)
    if mb_val >= 1.0:
        return f"{mb_val:.1f}MB" if mb_val < 10 else f"{int(round(mb_val))}MB"
    kb_val = max(1, int(round(num_bytes / 1024.0)))
    return f"{kb_val}KB"

def _update_and_get_user_bw(port_user_map: dict) -> dict:
    store = {"users": {}, "port_last": {}}
    if os.path.exists(USER_BW_STORE):
        try:
            with open(USER_BW_STORE, "r") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict) and "users" in loaded:
                    store = loaded
        except Exception:
            pass

    port_bytes = {}
    if os.path.exists(PORT_BW_FILE):
        try:
            with open(PORT_BW_FILE, "r") as f:
                port_bytes = json.load(f)
        except Exception:
            pass

    ss_tin = run_cmd("ss -tin state established 2>/dev/null").stdout
    cur_lport = None
    for ln in ss_tin.splitlines():
        if "127.0.0.1:" in ln and ("ESTAB" in ln or ln.strip().startswith("0 ")):
            cols = ln.split()
            if len(cols) >= 4:
                peer_col = cols[-1]
                if "127.0.0.1:" in peer_col:
                    try:
                        cur_lport = peer_col.rsplit(":", 1)[1]
                    except Exception:
                        cur_lport = None
        elif cur_lport and ("bytes_acked:" in ln or "bytes_received:" in ln):
            ba = re.search(r"bytes_acked:(\d+)", ln)
            br = re.search(r"bytes_received:(\d+)", ln)
            tot_k = (int(ba.group(1)) if ba else 0) + (int(br.group(1)) if br else 0)
            if tot_k > port_bytes.get(str(cur_lport), 0):
                port_bytes[str(cur_lport)] = tot_k
            cur_lport = None

    for p_str, uname in port_user_map.items():
        cur_b = int(port_bytes.get(str(p_str), 0))
        if cur_b <= 0:
            continue
        key_p = f"{uname}:{p_str}"
        last_b = int(store["port_last"].get(key_p, 0))
        delta = cur_b - last_b if cur_b >= last_b else cur_b
        if delta > 0:
            store["users"][uname] = int(store["users"].get(uname, 0)) + delta
            store["port_last"][key_p] = cur_b

    if len(store["port_last"]) > 4000:
        keys_to_keep = list(store["port_last"].keys())[-2000:]
        store["port_last"] = {k: store["port_last"][k] for k in keys_to_keep}

    try:
        atomic_write_json(USER_BW_STORE, store)
    except Exception:
        pass

    return store["users"]

def get_detailed_login_data_local() -> dict:
    res = {"ssh": {}, "vmess": {}, "vless": {}, "trojan": {}, "ip_times": {}, "ip_events": {}}
    now = int(time.time())
    now_hms = time.strftime("%H:%M:%S")

    port_to_ip = {}
    port_to_hms = {}
    if os.path.exists("/var/log/vpn-ws-map.log"):
        try:
            with open("/var/log/vpn-ws-map.log", "r", errors="ignore") as f:
                lines = f.readlines()[-5000:]
            for ln in lines:
                parts = ln.strip().split("|")
                if len(parts) >= 3 and parts[1].isdigit():
                    lp_num = int(parts[1])
                    port_to_ip[lp_num] = parts[2].strip()
                    if parts[0].isdigit():
                        port_to_hms[lp_num] = time.strftime("%H:%M:%S", time.localtime(int(parts[0])))
        except Exception:
            pass

    est_ssh_lports = set()
    est_xray_lports = set()
    ss_out = run_cmd("ss -tn state established 2>/dev/null").stdout
    for ln in ss_out.splitlines():
        cols = ln.split()
        if len(cols) >= 4:
            loc_col, peer_col = cols[-2], cols[-1]
            if ":90" in loc_col and "127.0.0.1:" in peer_col:
                try:
                    est_ssh_lports.add(int(peer_col.rsplit(":", 1)[1]))
                except Exception:
                    pass
            for xp in ("10001", "10002", "10003", "10004", "10005", "10006", "10007", "10008", "10009"):
                if f":{xp}" in loc_col and "127.0.0.1:" in peer_col:
                    try:
                        est_xray_lports.add(int(peer_col.rsplit(":", 1)[1]))
                    except Exception:
                        pass

    port_user_map = {}

    alive_db_pids = set()
    for pid_str in os.listdir("/proc"):
        if pid_str.isdigit():
            try:
                with open(f"/proc/{pid_str}/comm", "r") as cf:
                    if "dropbear" in cf.read().lower():
                        alive_db_pids.add(int(pid_str))
            except Exception:
                pass

    if os.path.exists("/var/log/dropbear.log"):
        try:
            with open("/var/log/dropbear.log", "r", errors="ignore") as f:
                db_lines = f.readlines()[-4000:]
            pid_auth_map = {}
            exited_pids = set()
            for ln in db_lines:
                m_pid = re.search(r"\[(\d+)\]", ln)
                if not m_pid:
                    continue
                pid_num = int(m_pid.group(1))
                if "Exit (" in ln or "Exit before auth" in ln:
                    exited_pids.add(pid_num)
                    pid_auth_map.pop(pid_num, None)
                    continue
                m_auth = re.search(r"Password auth succeeded for '([^']+)' from ([0-9a-fA-F\.\:]+):(\d+)", ln)
                if m_auth:
                    u_name = m_auth.group(1).strip()
                    src_ip = m_auth.group(2).strip()
                    src_port = int(m_auth.group(3))
                    port_user_map[str(src_port)] = u_name
                    pid_auth_map[pid_num] = (u_name, src_ip, src_port)

            for pid_num, (u_name, src_ip, src_port) in pid_auth_map.items():
                if pid_num not in alive_db_pids or pid_num in exited_pids:
                    continue
                if src_ip in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
                    if est_ssh_lports and src_port not in est_ssh_lports:
                        continue
                    rip = port_to_ip.get(src_port, "").split(":")[0].strip()
                    hms = port_to_hms.get(src_port, now_hms)
                else:
                    rip = src_ip
                    hms = now_hms
                if rip and not rip.startswith("127."):
                    res["ip_times"].setdefault(u_name, {})[rip] = hms
                    res["ip_events"].setdefault(u_name, []).append({"time": hms, "ip": rip})
                info_s = res["ssh"].setdefault(u_name, {"pids": 0, "used_str": "0MB"})
                info_s["pids"] += 1
        except Exception:
            pass

    ps_sshd = run_cmd("ps -eo pid,args 2>/dev/null | grep 'sshd: ' | grep -v grep").stdout
    for ln in ps_sshd.splitlines():
        m = re.search(r"^\s*(\d+)\s+sshd:\s+([a-zA-Z0-9_\-]+)", ln)
        if m:
            uname_s = m.group(2).strip()
            if uname_s not in ("root", "sshd"):
                info_s = res["ssh"].setdefault(uname_s, {"pids": 0, "used_str": "0MB"})
                info_s["pids"] += 1

    user_proto_map = {}
    if os.path.exists("/etc/xray/config.json"):
        try:
            with open("/etc/xray/config.json", "r") as xf:
                xcfg = json.load(xf)
            for ib in xcfg.get("inbounds", []):
                p_name = ib.get("protocol", "").lower()
                if p_name in ("vmess", "vless", "trojan"):
                    for cl in ib.get("settings", {}).get("clients", []):
                        em = cl.get("email", "")
                        un = em.split("|")[-1]
                        for pfx_t in ("vmess-", "vless-", "trojan-", "ss-"):
                            if un.startswith(pfx_t):
                                un = un[len(pfx_t):]
                                break
                        if un:
                            user_proto_map[un] = p_name
        except Exception:
            pass

    if os.path.exists("/var/log/xray/access.log"):
        try:
            with open("/var/log/xray/access.log", "r", errors="ignore") as f:
                x_lines = f.readlines()[-4000:]
            cutoff_ts = now - 75
            temp_xray = {"vmess": {}, "vless": {}, "trojan": {}}

            for ln in x_lines:
                if "email:" not in ln or "accepted" not in ln:
                    continue
                m_dt = re.match(r"^(\d{4}/\d{2}/\d{2}\s+(\d{2}:\d{2}:\d{2}))", ln)
                is_recent = True
                log_hms = now_hms
                if m_dt:
                    log_hms = m_dt.group(2)
                    try:
                        l_ts = int(calendar.timegm(time.strptime(m_dt.group(1), "%Y/%m/%d %H:%M:%S")))
                        if l_ts < cutoff_ts:
                            is_recent = False
                    except Exception:
                        pass

                m_src = re.search(r"from\s+(?:tcp:)?([0-9a-fA-F\.\:]+):(\d+)\s+accepted", ln)
                m_em = re.search(r"email:\s*([^\s]+)", ln)
                if not m_src or not m_em:
                    continue
                src_ip = m_src.group(1).strip()
                src_port = int(m_src.group(2))
                raw_email = m_em.group(1).strip()

                p_detected = None
                for pt in ("vmess", "vless", "trojan"):
                    if f"[{pt}" in ln or raw_email.startswith(f"{pt}|") or raw_email.startswith(f"{pt}-"):
                        p_detected = pt
                        break

                u_name = raw_email.split("|")[-1]
                for pfx_tag in ("vmess-", "vless-", "trojan-", "ss-"):
                    if u_name.startswith(pfx_tag):
                        u_name = u_name[len(pfx_tag):]
                        break

                if not p_detected:
                    p_detected = user_proto_map.get(u_name, "vless")

                port_user_map[str(src_port)] = u_name

                if src_ip in ("127.0.0.1", "::1"):
                    if (src_port in est_xray_lports) or is_recent:
                        rip = port_to_ip.get(src_port, "").split(":")[0].strip()
                        hms = port_to_hms.get(src_port, log_hms)
                        if rip and not rip.startswith("127."):
                            res["ip_times"].setdefault(u_name, {})[rip] = hms
                            res["ip_events"].setdefault(u_name, []).append({"time": hms, "ip": rip})
                            info = temp_xray[p_detected].setdefault(u_name, {"ips": set(), "port": src_port})
                            info["ips"].add(rip)
                            info["port"] = src_port
                else:
                    if is_recent and not src_ip.startswith("127."):
                        res["ip_times"].setdefault(u_name, {})[src_ip] = log_hms
                        res["ip_events"].setdefault(u_name, []).append({"time": log_hms, "ip": src_ip})
                        info = temp_xray[p_detected].setdefault(u_name, {"ips": set(), "port": src_port})
                        info["ips"].add(src_ip)
                        info["port"] = src_port

            for pt in ("vmess", "vless", "trojan"):
                for un, d_val in temp_xray[pt].items():
                    res[pt][un] = {
                        "ip_count": max(1, len(d_val["ips"])),
                        "port": d_val["port"] % 10000 if d_val["port"] > 10000 else d_val["port"],
                        "used_str": "1MB"
                    }
        except Exception:
            pass

    user_bw_totals = _update_and_get_user_bw(port_user_map)
    for u_name, d_ssh in res["ssh"].items():
        d_ssh["used_str"] = format_user_bw_usage(int(user_bw_totals.get(u_name, 0)))
    for pt in ("vmess", "vless", "trojan"):
        for u_name, d_x in res[pt].items():
            d_x["used_str"] = format_user_bw_usage(int(user_bw_totals.get(u_name, 0)))

    return res

def get_detailed_login_data(srv_row) -> dict:
    if not srv_row or srv_row["is_local"] == 1:
        return get_detailed_login_data_local()
    try:
        ssh = connect_remote_ssh(srv_row, timeout=8)
        cmd = "python3 -c \"import sys, json; sys.path.append('/etc/vpn-bot'); import vpn_engine as e; print('LOGIN_DETAIL:' + json.dumps(e.get_detailed_login_data_local()))\""
        _, out_str, _ = exec_ssh_sync(ssh, cmd, timeout=10)
        ssh.close()
        for line in out_str.splitlines():
            if line.startswith("LOGIN_DETAIL:"):
                return json.loads(line.split("LOGIN_DETAIL:", 1)[1].strip())
    except Exception:
        pass
    return {"ssh": {}, "vmess": {}, "vless": {}, "trojan": {}, "ip_times": {}, "ip_events": {}}
EOF_EMBED_FILE
chmod +x /etc/vpn-bot/vpn_engine.py 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/bot.py
#!/usr/bin/env python3
import asyncio
import html
import os
import random
import re
import sqlite3
import subprocess
import time
import uuid
from datetime import datetime, timedelta
import paramiko

from aiogram import Bot, Dispatcher, F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    FSInputFile,
    Message,
)

try:
    from aiogram.types import CopyTextButton
    HAS_NATIVE_COPY = True
except ImportError:
    HAS_NATIVE_COPY = False

import vpn_engine as engine

ENV_CONFIG = {}
with open("/etc/vpn-bot/config.env", "r") as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            ENV_CONFIG[k.strip()] = v.strip().strip('"')

BOT_TOKEN = ENV_CONFIG["BOT_TOKEN"]
ADMIN_ID = int(ENV_CONFIG["ADMIN_ID"])
DEFAULT_DOMAIN = ENV_CONFIG["DOMAIN"]
PUBLIC_IP = ENV_CONFIG.get("PUBLIC_IP", "127.0.0.1")
DEFAULT_CITY = ENV_CONFIG.get("VPS_CITY", "Singapore")
DEFAULT_ISP = ENV_CONFIG.get("VPS_ISP", "DigitalOcean, LLC")

DB_PATH = "/etc/vpn-bot/vpn_data.db"

def mask_str(s: str) -> str:
    if not s or s == "-":
        return "-"
    s = str(s).strip()
    if "-" in s:
        pfx, rest = s.split("-", 1)
        if len(rest) <= 3:
            return f"{pfx}-{rest[0]}***"
        elif len(rest) <= 5:
            return f"{pfx}-{rest[:2]}***"
        return f"{pfx}-{rest[:2]}***{rest[-2:]}"
    if len(s) <= 3:
        return s[0] + "***"
    elif len(s) <= 5:
        return s[:2] + "***"
    return s[:2] + "***" + s[-2:]

def apply_account_prefix(raw_uname: str) -> str:
    raw_uname = raw_uname.strip()
    if get_setting("prefix_enabled", "1") == "1":
        pfx = get_setting("account_prefix", "sunek").strip().strip("-")
        if pfx:
            low_pfx = f"{pfx.lower()}-"
            if raw_uname.lower().startswith(low_pfx):
                return f"{pfx}-{raw_uname[len(low_pfx):]}"
            return f"{pfx}-{raw_uname}"
    return raw_uname

def resequence_servers_db():
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM servers ORDER BY is_local DESC, id ASC").fetchall()
        for idx, r in enumerate(rows, 1):
            old_id = r["id"]
            if old_id != idx:
                conn.execute("UPDATE servers SET id=? WHERE id=?", (-idx, old_id))
                conn.execute("UPDATE accounts SET server_id=? WHERE server_id=?", (-idx, old_id))
        conn.execute("UPDATE servers SET id = -id WHERE id < 0")
        conn.execute("UPDATE accounts SET server_id = -server_id WHERE server_id < 0")
        conn.execute("DELETE FROM sqlite_sequence WHERE name='servers'")
        if rows:
            conn.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('servers', ?)", (len(rows),))
        conn.commit()

def db_conn():
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with db_conn() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, host TEXT, city TEXT, isp TEXT,
            ssh_port INTEGER DEFAULT 22, ssh_user TEXT DEFAULT 'root', ssh_pass TEXT DEFAULT '',
            max_users INTEGER DEFAULT 100, max_bw_gb INTEGER DEFAULT 1000,
            speed_mbps INTEGER DEFAULT 0, is_local INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS relays (
            id INTEGER PRIMARY KEY AUTOINCREMENT, country TEXT, address TEXT, port INTEGER,
            uuid TEXT, protocol TEXT DEFAULT 'vless', is_active INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, server_id INTEGER DEFAULT 1,
            protocol TEXT, username TEXT UNIQUE, secret TEXT, ip_limit INTEGER DEFAULT 2,
            quota_gb INTEGER DEFAULT 50, speed_mbps INTEGER DEFAULT 0, created_at INTEGER,
            expired_at INTEGER, is_trial INTEGER DEFAULT 0, locked_until INTEGER DEFAULT 0,
            strike_count INTEGER DEFAULT 0, violation_level INTEGER DEFAULT 0,
            last_ips TEXT DEFAULT '', active_sessions INTEGER DEFAULT 0,
            custom_bug TEXT DEFAULT '', bug_mode TEXT DEFAULT 'sni'
        );
        CREATE TABLE IF NOT EXISTS users (
            user_id INTEGER PRIMARY KEY, username TEXT DEFAULT '', first_name TEXT DEFAULT '',
            is_banned INTEGER DEFAULT 0, custom_max_create INTEGER DEFAULT -1, joined_at INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS create_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, username TEXT,
            protocol TEXT, is_trial INTEGER DEFAULT 0, created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS detected_topics (
            chat_id INTEGER, thread_id INTEGER, chat_title TEXT, updated_at INTEGER,
            PRIMARY KEY (chat_id, thread_id)
        );
        CREATE TABLE IF NOT EXISTS bug_presets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bug_host TEXT UNIQUE
        );
        CREATE TABLE IF NOT EXISTS activity_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, event TEXT, detail TEXT
        );
        """)
        for alter_sql in (
            "ALTER TABLE accounts ADD COLUMN custom_bug TEXT DEFAULT ''",
            "ALTER TABLE accounts ADD COLUMN bug_mode TEXT DEFAULT 'sni'",
            "ALTER TABLE servers ADD COLUMN max_bw_gb INTEGER DEFAULT 1000",
            "ALTER TABLE servers ADD COLUMN speed_mbps INTEGER DEFAULT 0",
            "ALTER TABLE servers ADD COLUMN ipv4 TEXT DEFAULT ''",
        ):
            try:
                conn.execute(alter_sql)
            except Exception:
                pass

        default_bugs = [
            "v.whatsapp.net", "ava.game.naver.com", "quiz.vidio.com",
            "vplay.iflix.com", "graph.instagram.com", "zaintest.vuclip.com", "104.18.2.2"
        ]
        cur_b = conn.execute("SELECT COUNT(*) as c FROM bug_presets").fetchone()["c"]
        if cur_b == 0:
            for b in default_bugs:
                conn.execute("INSERT OR IGNORE INTO bug_presets (bug_host) VALUES (?)", (b,))

        defaults = {
            "welcome_text": "", "welcome_photo": "", "login_report_enabled": "0", "login_report_interval_min": "60", "login_topic_id": "0", "login_report_mask": "0", "login_report_show_ip": "1", "prefix_enabled": "1", "account_prefix": "sunek", "bot_theme": "default", "auto_heal_enabled": "1", "notif_server_status": "1",
            "bot_status": "1", "lock_enabled": "1", "lock_duration_min": "5",
            "lock_strikes": "1", "lock_tiered": "1", "default_days": "7",
            "trial_minutes": "30", "default_ip_limit": "2", "default_quota_gb": "50",
            "default_speed_mbps": "0", "max_users_per_vps": "100", "user_create_max": "1",
            "user_create_days": "3", "trial_create_max": "3", "notif_create_group": "1",
            "force_join_chat": "", "force_join_link": "", "group_chat_id": "", "group_topic_id": "0",
            "create_topic_id": "0", "bug_host": "v.whatsapp.net"
        }
        for k, v in defaults.items():
            conn.execute("INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)", (k, v))
        cur = conn.execute("SELECT COUNT(*) as c FROM servers WHERE is_local=1").fetchone()
        if cur["c"] == 0:
            conn.execute(
                "INSERT INTO servers (name, host, city, isp, max_users, max_bw_gb, speed_mbps, is_local) VALUES (?, ?, ?, ?, 100, 1000, 0, 1)",
                ("Server Utama", DEFAULT_DOMAIN, DEFAULT_CITY, DEFAULT_ISP)
            )
        conn.commit()
    try:
        os.chmod(DB_PATH, 0o600)
    except Exception:
        pass

def get_setting(key, default=""):
    with db_conn() as conn:
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return row["value"] if row is not None else default

UNLIMITED_CAPABLE_KEYS = {
    "default_days", "default_ip_limit", "default_quota_gb",
    "default_speed_mbps", "user_create_max",
    "group_topic_id", "create_topic_id", "login_topic_id"
}

def get_int_setting(key: str, default: int, min_val: int = 0) -> int:
    if key in UNLIMITED_CAPABLE_KEYS:
        min_val = 0
    raw = str(get_setting(key, str(default))).strip()
    if raw.lower() in ("0", "unlimited", "unl", "inf"):
        return 0 if min_val <= 0 else min_val
    m = re.search(r"-?\d+", raw)
    val = int(m.group(0)) if m else default
    return max(min_val, val)


def set_setting(key, value):
    with db_conn() as conn:
        conn.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (key, str(value)))
        conn.commit()

def log_activity(event, detail):
    with db_conn() as conn:
        conn.execute("INSERT INTO activity_logs (ts, event, detail) VALUES (?, ?, ?)", (int(time.time()), event, detail))
        conn.commit()

def record_group_topic(msg: Message):
    if msg.chat and msg.chat.id < 0:
        cid = msg.chat.id
        tid = msg.message_thread_id or 0
        title = msg.chat.title or str(cid)
        with db_conn() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO detected_topics (chat_id, thread_id, chat_title, updated_at) VALUES (?, ?, ?, ?)",
                (cid, tid, title, int(time.time()))
            )
            conn.commit()

def sync_user_profile(tg_user):
    if not tg_user:
        return
    now = int(time.time())
    uname = tg_user.username or ""
    fname = tg_user.first_name or "User"
    with db_conn() as conn:
        row = conn.execute("SELECT user_id FROM users WHERE user_id=?", (tg_user.id,)).fetchone()
        if not row:
            conn.execute(
                "INSERT INTO users (user_id, username, first_name, is_banned, custom_max_create, joined_at) VALUES (?, ?, ?, 0, -1, ?)",
                (tg_user.id, uname, fname, now)
            )
        else:
            conn.execute("UPDATE users SET username=?, first_name=? WHERE user_id=?", (uname, fname, tg_user.id))
        conn.commit()

def check_user_access(user_id: int):
    if user_id == ADMIN_ID:
        return True, ""
    if get_setting("bot_status", "1") != "1":
        return False, "⚠️ Mohon maaf, Bot sedang dinonaktifkan sementara oleh Admin (Maintenance)."
    with db_conn() as conn:
        u = conn.execute("SELECT is_banned FROM users WHERE user_id=?", (user_id,)).fetchone()
        if u and u["is_banned"] == 1:
            return False, "⛔ ID Telegram Anda telah diblokir (Banned) oleh Admin."
    return True, ""

def check_user_create_quota(user_id: int, is_trial: int):
    if user_id == ADMIN_ID:
        return True, ""
    now = int(time.time())
    with db_conn() as conn:
        u = conn.execute("SELECT custom_max_create FROM users WHERE user_id=?", (user_id,)).fetchone()
        custom_max = u["custom_max_create"] if u else -1
        if is_trial == 1:
            t_max = get_int_setting("trial_create_max", 3, 0)
            if t_max <= 0:
                return True, ""
            since = now - 86400
            rows = conn.execute(
                "SELECT created_at FROM create_history WHERE user_id=? AND is_trial=1 AND created_at >= ? ORDER BY created_at ASC",
                (user_id, since)
            ).fetchall()
            if len(rows) >= t_max:
                next_str = datetime.fromtimestamp(rows[0]["created_at"] + 86400).strftime("%d/%m/%Y %H:%M WIB")
                return False, f"⛔ Batas Trial tercapai ({len(rows)}/{t_max}x per hari). Bisa buat lagi pada {next_str}."
            return True, ""
        else:
            u_max = custom_max if custom_max >= 0 else get_int_setting("user_create_max", 1, 0)
            u_days = get_int_setting("user_create_days", 3, 1)
            if u_max <= 0:
                return True, ""
            window_sec = u_days * 86400
            rows = conn.execute(
                "SELECT created_at FROM create_history WHERE user_id=? AND is_trial=0 AND created_at >= ? ORDER BY created_at ASC",
                (user_id, now - window_sec)
            ).fetchall()
            if len(rows) >= u_max:
                next_str = datetime.fromtimestamp(rows[0]["created_at"] + window_sec).strftime("%d/%m/%Y %H:%M WIB")
                return False, f"⛔ Batas buat akun tercapai ({u_max}x dalam {u_days} hari).\nBisa buat lagi pada: {next_str}"
            return True, ""

class FormState(StatesGroup):
    create_username = State()
    create_password = State()
    admin_set_value = State()
    admin_edit_banner = State()
    admin_add_vps = State()
    admin_add_relay = State()
    admin_search_user = State()
    admin_set_user_quota = State()
    admin_manual_topic = State()
    admin_edit_welcome_text = State()
    admin_edit_welcome_photo = State()
    user_input_bug = State()
    ext_input_link = State()
    ext_input_bug = State()
    admin_add_bug_preset = State()
    admin_broadcast_msg = State()
    admin_vps_edit_val = State()
    vps_add_name = State()
    vps_add_host = State()
    vps_add_ipv4 = State()
    vps_add_port = State()
    vps_add_pass = State()
    vps_edit_name = State()
    vps_edit_host = State()
    vps_edit_ipv4 = State()
    vps_edit_port = State()
    vps_edit_pass = State()
    user_bug_scanner = State()
    admin_change_domain_input = State()
    admin_wj_step1_target = State()
    admin_wj_step2_link = State()
    admin_set_prefix = State()
    admin_login_rep_interval = State()

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()
router = Router()
dp.include_router(router)

def build_force_join_prompt():
    fj_chat = get_setting("force_join_chat", "").strip()
    fj_link = get_setting("force_join_link", "").strip()
    if not fj_link:
        if fj_chat.startswith("@"):
            fj_link = f"https://t.me/{fj_chat.lstrip('@')}"
        elif fj_chat.startswith("http"):
            fj_link = fj_chat
        else:
            fj_link = "https://t.me/"
    txt = (
        "⚠️ <b>AKSES WAJIB BERGABUNG CHANNEL / GRUP</b>\n"
        "────────────────────────────\n"
        f"Untuk menggunakan layanan bot ini, Anda wajib bergabung terlebih dahulu ke:\n"
        f"📢 <b>Target:</b> <code>{html.escape(fj_chat)}</code>\n\n"
        "Silakan klik tombol <b>Gabung Sekarang</b> di bawah, lalu klik <b>Saya Sudah Bergabung</b>:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📢 Gabung Channel / Grup Sekarang", url=fj_link)],
        [InlineKeyboardButton(text="🔄 Saya Sudah Bergabung (Cek Ulang)", callback_data="back_home")]
    ])
    return txt, kb

async def check_force_join(user_id: int) -> bool:
    if user_id == ADMIN_ID:
        return True
    fj = get_setting("force_join_chat", "").strip()
    if not fj:
        return True
    try:
        member = await bot.get_chat_member(chat_id=fj, user_id=user_id)
        return member.status in ("member", "administrator", "creator")
    except Exception:
        return True

def user_has_locked_account(user_id: int) -> bool:
    now = int(time.time())
    with db_conn() as conn:
        row = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE user_id=? AND locked_until > ?", (user_id, now)).fetchone()
        return row["c"] > 0

def make_copy_btn(label: str, text_val: str, fallback_cb: str) -> InlineKeyboardButton:
    if HAS_NATIVE_COPY and 1 <= len(text_val) <= 256:
        return InlineKeyboardButton(text=label, copy_text=CopyTextButton(text=text_val))
    return InlineKeyboardButton(text=label, callback_data=fallback_cb)

def build_account_details_and_kb(acc_row, srv_row, back_target="back_home"):
    proto = acc_row["protocol"]
    uname = acc_row["username"]
    secret = acc_row["secret"]
    ip_limit = acc_row["ip_limit"]
    acc_id = acc_row["id"]
    host, city, isp = srv_row["host"], srv_row["city"], srv_row["isp"]
    bug_host = get_setting("bug_host", "bug.com")

    if acc_row["is_trial"] == 1:
        rem_min = max(1, int((acc_row["expired_at"] - acc_row["created_at"]) / 60))
        exp_display = f"{rem_min} Menit"
    else:
        exp_display = datetime.fromtimestamp(acc_row["expired_at"]).strftime("%Y-%m-%d")

    kb_rows = []
    if proto == "ssh":
        out_html = engine.format_ssh_html(host, uname, secret, bug_host=bug_host, ip_limit=ip_limit, exp_str=exp_display)
        p_ws = "GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
        p_enh = f"PATCH / HTTP/1.1[crlf]Host: [host][crlf]Host: {bug_host}[crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
        kb_rows.extend([
            [make_copy_btn("📋 Salin Username", uname, f"cp:{acc_id}:user"), make_copy_btn("📋 Salin Password", secret, f"cp:{acc_id}:pass")],
            [make_copy_btn("📋 Salin SSH WS (80)", f"{host}:80@{uname}:{secret}", f"cp:{acc_id}:ssh_ws"), make_copy_btn("📋 Salin SSH SSL (443)", f"{host}:443@{uname}:{secret}", f"cp:{acc_id}:ssh_ssl")],
            [make_copy_btn("📋 Salin SSH UDP", f"{host}:1-65535@{uname}:{secret}", f"cp:{acc_id}:ssh_udp"), make_copy_btn("📋 Salin SlowDNS", f"ns-{host}:5300@{uname}:{secret}", f"cp:{acc_id}:ssh_dns")],
            [make_copy_btn("📋 Salin Payload WS", p_ws, f"cp:{acc_id}:p_ws"), make_copy_btn("📋 Salin Payload Enhanced", p_enh, f"cp:{acc_id}:p_enh")]
        ])
    elif proto == "vmess":
        out_html = engine.format_vmess_html(uname, city, isp, host, secret, exp_display, ip_limit=ip_limit)
        l_wstls = engine.make_vmess_b64(uname, host, 443, secret, "ws", "/vmess", "tls")
        l_wsntls = engine.make_vmess_b64(uname, host, 80, secret, "ws", "/vmess", "none")
        l_grpc = engine.make_vmess_b64(uname, host, 443, secret, "grpc", "vmess", "tls")
        l_uptls = engine.make_vmess_b64(uname, host, 443, secret, "httpupgrade", "/upvmess", "tls")
        l_upntls = engine.make_vmess_b64(uname, host, 80, secret, "httpupgrade", "/upvmess", "none")
        kb_rows.extend([
            [make_copy_btn("📋 Salin UUID", secret, f"cp:{acc_id}:uuid")],
            [make_copy_btn("📋 Salin WS TLS", l_wstls, f"cp:{acc_id}:wstls"), make_copy_btn("📋 Salin WS No-TLS", l_wsntls, f"cp:{acc_id}:wsntls")],
            [make_copy_btn("📋 Salin gRPC", l_grpc, f"cp:{acc_id}:grpc"), make_copy_btn("📋 Salin Upgrade TLS", l_uptls, f"cp:{acc_id}:uptls")],
            [make_copy_btn("📋 Salin Upgrade No-TLS", l_upntls, f"cp:{acc_id}:upntls")]
        ])
    elif proto == "vless":
        out_html = engine.format_vless_html(uname, city, isp, host, secret, exp_display, ip_limit=ip_limit)
        l_wstls = f"vless://{secret}@{host}:443?path=/vless&security=tls&encryption=none&host={host}&type=ws&sni={host}#{uname}"
        l_wsntls = f"vless://{secret}@{host}:80?path=/vless&security=none&encryption=none&host={host}&type=ws#{uname}"
        l_grpc = f"vless://{secret}@{host}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless&sni={host}#{uname}"
        l_uptls = f"vless://{secret}@{host}:443?path=/upvless&security=tls&encryption=none&host={host}&type=httpupgrade&sni={host}#{uname}"
        l_upntls = f"vless://{secret}@{host}:80?path=/upvless&security=none&encryption=none&host={host}&type=httpupgrade#{uname}"
        kb_rows.extend([
            [make_copy_btn("📋 Salin UUID", secret, f"cp:{acc_id}:uuid")],
            [make_copy_btn("📋 Salin WS TLS", l_wstls, f"cp:{acc_id}:wstls"), make_copy_btn("📋 Salin WS No-TLS", l_wsntls, f"cp:{acc_id}:wsntls")],
            [make_copy_btn("📋 Salin gRPC", l_grpc, f"cp:{acc_id}:grpc"), make_copy_btn("📋 Salin Upgrade TLS", l_uptls, f"cp:{acc_id}:uptls")],
            [make_copy_btn("📋 Salin Upgrade No-TLS", l_upntls, f"cp:{acc_id}:upntls")]
        ])
    else:
        out_html = engine.format_trojan_html(uname, city, isp, host, secret, exp_display, ip_limit=ip_limit)
        l_wstls = f"trojan://{secret}@{host}:443?path=/trojan&security=tls&host={host}&type=ws&sni={host}#{uname}"
        l_grpc = f"trojan://{secret}@{host}:443?mode=gun&security=tls&type=grpc&serviceName=trojan&sni={host}#{uname}"
        l_uptls = f"trojan://{secret}@{host}:443?path=/uptrojan&security=tls&host={host}&type=httpupgrade&sni={host}#{uname}"
        kb_rows.extend([
            [make_copy_btn("📋 Salin Key / UUID", secret, f"cp:{acc_id}:uuid")],
            [make_copy_btn("📋 Salin WS TLS", l_wstls, f"cp:{acc_id}:wstls"), make_copy_btn("📋 Salin gRPC", l_grpc, f"cp:{acc_id}:grpc")],
            [make_copy_btn("📋 Salin Upgrade TLS", l_uptls, f"cp:{acc_id}:uptls")]
        ])

    kb_rows.append([InlineKeyboardButton(text="🎯 Inject Bug & Multi-Client", callback_data=f"inj_menu:{acc_id}")])
    if acc_row["locked_until"] <= int(time.time()):
        if proto in ("vmess", "vless", "trojan"):
            kb_rows.append([
                InlineKeyboardButton(text="🔄 Tukar Protokol", callback_data=f"chg_proto_menu:{acc_id}"),
                InlineKeyboardButton(text="🌐 Pindah Server", callback_data=f"move_srv_menu:{acc_id}")
            ])
        else:
            kb_rows.append([
                InlineKeyboardButton(text="🌐 Pindah Server", callback_data=f"move_srv_menu:{acc_id}")
            ])
        kb_rows.append([InlineKeyboardButton(text=f"🗑 Hapus Akun ({uname})", callback_data=f"del_my:{acc_id}")])

    kb_rows.append([
        InlineKeyboardButton(text="👤 Akun Saya", callback_data="my_accounts"),
        InlineKeyboardButton(text="🏠 Menu Utama", callback_data="back_home")
    ])
    return out_html, InlineKeyboardMarkup(inline_keyboard=kb_rows)

def build_server_rules_text(user_id: int) -> str:
    now = int(time.time())
    c_max = get_int_setting("user_create_max", 1, 0)
    c_days = get_int_setting("user_create_days", 3, 1)
    reg_days = get_int_setting("default_days", 1, 0)
    trl_mins = get_int_setting("trial_minutes", 30, 1)
    q_gb = get_int_setting("default_quota_gb", 0, 0)
    s_mbps = get_int_setting("default_speed_mbps", 0, 0)
    ip_lim = get_int_setting("default_ip_limit", 2, 0)
    lock_dur = get_int_setting("lock_duration_min", 15, 1)

    with db_conn() as conn:
        u = conn.execute("SELECT custom_max_create FROM users WHERE user_id=?", (user_id,)).fetchone()
        custom_max = u["custom_max_create"] if u and u["custom_max_create"] is not None else -1
        used_cnt = conn.execute(
            "SELECT COUNT(*) as c FROM create_history WHERE user_id=? AND is_trial=0 AND created_at >= ?",
            (user_id, now - (c_days * 86400))
        ).fetchone()["c"]

    eff_max = custom_max if custom_max >= 0 else c_max
    if eff_max > 0:
        jatah_str = f"Maks {eff_max} Akun / {c_days} Hari (Terpakai: {used_cnt}/{eff_max})"
    else:
        jatah_str = f"Unlimited (Terpakai: {used_cnt})"

    reg_lbl = f"{reg_days} Hari" if reg_days > 0 else "Unlimited"
    bw_lbl = f"{q_gb} GB" if (0 < q_gb < 900) else "Unlimited"
    spd_lbl = f"{s_mbps} Mbps" if s_mbps > 0 else "Unlimited"
    ip_lbl = f"{ip_lim} IP / Akun" if ip_lim > 0 else "Unlimited IP"

    return (
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "📜 <b>ATURAN &amp; KETENTUAN SERVER</b>\n"
        f"• <b>Jatah Buat Akun:</b> {jatah_str}\n"
        f"• <b>Masa Aktif Reguler:</b> {reg_lbl} | <b>Trial:</b> {trl_mins} Menit\n"
        f"• <b>Kuota Bandwidth:</b> {bw_lbl} | <b>Speed Limit:</b> {spd_lbl}\n"
        f"• <b>Batas Login (Limit IP):</b> {ip_lbl}\n"
        f"• <b>Sanksi Multi-Login:</b> Auto-Lock {lock_dur} Menit (Maks 3x Pelanggaran)\n"
        "• <b>Larangan Keras:</b> Dilarang Torrent, DDoS, Spamming &amp; Multi-Login!"
    )

def build_admin_dashboard_text(user_id: int = None, include_rules: bool = True) -> str:
    now = int(time.time())
    with db_conn() as conn:
        tot_users = conn.execute("SELECT COUNT(*) as c FROM users").fetchone()["c"]
        tot_accs = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE expired_at > ?", (now,)).fetchone()["c"]
        locked_accs = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE locked_until > ? AND expired_at > ?", (now, now)).fetchone()["c"]
        srvs = conn.execute("SELECT * FROM servers").fetchall()

    default_max_u = get_int_setting("max_users_per_vps", 100, 1)
    st = engine.get_dashboard_stats()

    header = (
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👥 Total User Bot: <b>{tot_users}</b> | Total Akun: <b>{tot_accs}</b> (🔒 <b>{locked_accs}</b>)\n"
        f"⚙️ Service Utama: Xray {st['xray_st']} | SSH {st['ssh_st']} | Dropbear {st['db_st']}\n"
        f"🌐 Proxy Utama: HAProxy {st['hap_st']} | Nginx {st['ngx_st']}\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
    )

    srv_blocks = []
    for s in srvs:
        with db_conn() as conn:
            s_accs = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (s["id"], now)).fetchone()["c"]
        s_max_u = s["max_users"] if "max_users" in s.keys() and s["max_users"] else default_max_u
        if s["is_local"] == 1:
            srv_blocks.append(
                f"🖥 <b>{html.escape(s['name'])} (🟢 Online)</b>\n"
                f"├ Domain: <code>{html.escape(s['host'])}</code>\n"
                f"├ CPU / RAM: <code>{st['cpu_pct']} | {st['ram_str']}</code>\n"
                f"├ Disk VPS: <code>{st['disk_str']}</code>\n"
                f"├ Kapasitas &amp; Kuota User: <code>{s_accs} / {s_max_u} Akun | {st['bw_gb_str']}</code>\n"
                f"📊 <b>[ TRAFFIC RATE (LIVE) ]</b>\n"
                f"⬇ IN   : <code>{st['in_mbps']}</code>\n"
                f"⬆ OUT  : <code>{st['out_mbps']}</code>\n"
                f"📈 <b>[ VNSTAT BANDWIDTH ]</b>\n"
                f"🗓 Day  : <code>{st['vnstat_day']}</code>\n"
                f"📆 Mth  : <code>{st['vnstat_mth']}</code>"
            )
        else:
            rst = engine.get_remote_dashboard_stats(s)
            if rst.get("online"):
                srv_blocks.append(
                    f"🖥 <b>{html.escape(s['name'])} (🟢 Online)</b>\n"
                    f"├ Domain: <code>{html.escape(s['host'])}</code>\n"
                    f"├ CPU / RAM: <code>{rst['cpu_pct']} | {rst['ram_str']}</code>\n"
                    f"├ Disk VPS: <code>{rst['disk_str']}</code>\n"
                    f"├ Kapasitas &amp; Kuota User: <code>{s_accs} / {s_max_u} Akun | {rst['bw_gb_str']}</code>\n"
                    f"📊 <b>[ TRAFFIC RATE (LIVE) ]</b>\n"
                    f"⬇ IN   : <code>{rst['in_mbps']}</code>\n"
                    f"⬆ OUT  : <code>{rst['out_mbps']}</code>\n"
                    f"📈 <b>[ VNSTAT BANDWIDTH ]</b>\n"
                    f"🗓 Day  : <code>{rst['vnstat_day']}</code>\n"
                    f"📆 Mth  : <code>{rst['vnstat_mth']}</code>"
                )
            else:
                srv_blocks.append(
                    f"🖥 <b>{html.escape(s['name'])} (🔴 Offline / Cek Login SSH)</b>\n"
                    f"├ Domain: <code>{html.escape(s['host'])}</code>\n"
                    f"╰ Kapasitas User: <code>{s_accs} / {s_max_u} Akun</code>"
                )

    body = header + "\n" + "\n\n".join(srv_blocks)
    if include_rules:
        uid = user_id if user_id is not None else ADMIN_ID
        body += "\n\n" + build_server_rules_text(uid)
    return body


THEMES_CATALOG = {
    "default": {
        "name": "Clean Minimalist (Default)",
        "title": "<b>VPN TUNNELING PANEL</b>",
        "line": "────────────────────────────",
        "bullet": "•",
        "btn_create": "🦆 Buat",
        "btn_trial": "🐒 Trial",
    },
    "cyberpunk": {
        "name": "Cyberpunk Neon ⚡",
        "title": "⚡ <b>𝗖𝗬𝗕𝗘𝗥𝗣𝗨𝗡𝗞 𝗩𝗣𝗡 𝗡𝗘𝗧𝗪𝗢𝗥𝗞</b> ⚡",
        "line": "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "bullet": "⚡",
        "btn_create": "⚡ Buat",
        "btn_trial": "🧪 Trial",
    },
    "royalgold": {
        "name": "Royal Gold VVIP 👑",
        "title": "👑 <b>𝗥𝗢𝗬𝗔𝗟 𝗩𝗩𝗜𝗣 𝗧𝗨𝗡𝗡𝗘𝗟𝗜𝗡𝗚</b> 👑",
        "line": "════════════════════════════",
        "bullet": "⚜️",
        "btn_create": "👑 Buat",
        "btn_trial": "💎 Trial",
    },
    "matrix": {
        "name": "Hacker Matrix 💻",
        "title": "💻 <b>[ ROOT@MATRIX-VPN-NODE ]</b> 💻",
        "line": "============================",
        "bullet": "▸",
        "btn_create": "💻 Buat",
        "btn_trial": "🔓 Trial",
    },
    "gaming": {
        "name": "Gaming Pro Extreme 🎮",
        "title": "🎮 <b>𝗚𝗔𝗠𝗜𝗡𝗚 𝗣𝗥𝗢 𝗨𝗟𝗧𝗥𝗔 𝗩𝗣𝗡</b> 🔥",
        "line": "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬",
        "bullet": "🔥",
        "btn_create": "🎮 Buat",
        "btn_trial": "🚀 Trial",
    },
}

def get_active_theme() -> dict:
    t_key = get_setting("bot_theme", "default")
    return THEMES_CATALOG.get(t_key, THEMES_CATALOG["default"])

def get_current_main_domain() -> str:
    with db_conn() as conn:
        row = conn.execute("SELECT host FROM servers WHERE is_local=1 LIMIT 1").fetchone()
        if row and row["host"]:
            return row["host"]
    return DEFAULT_DOMAIN

def format_welcome_caption(user_id: int) -> str:
    now = int(time.time())
    cur_domain = get_current_main_domain()
    th = get_active_theme()
    b = th["bullet"]
    line_sep = th["line"]

    with db_conn() as conn:
        total_acc = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE expired_at > ?", (now,)).fetchone()["c"]
        srv_cnt = conn.execute("SELECT COUNT(*) as c FROM servers").fetchone()["c"]
    bot_st = "🟢 Online" if get_setting("bot_status", "1") == "1" else "🔴 Maintenance (Off)"
    c_max = get_int_setting("user_create_max", 1, 0)
    c_days = get_int_setting("user_create_days", 3, 1)
    def_days = get_int_setting("default_days", 1, 0)
    ip_lim = get_int_setting("default_ip_limit", 2, 0)

    buat_akun_short = f"{c_max}× {c_days}d" if c_max > 0 else "Unlimited"
    d_lbl = f"{def_days}d" if def_days > 0 else "Unlimited"
    ip_lbl = f"{ip_lim} IP" if ip_lim > 0 else "Unlimited IP"
    aktif_akun_short = f"{d_lbl} | {ip_lbl}"

    custom_tpl = get_setting("welcome_text", "").strip()
    if custom_tpl:
        res = custom_tpl
        replacements = {
            "{domain}": cur_domain,
            "{lokasi}": DEFAULT_CITY,
            "{isp}": DEFAULT_ISP,
            "{limit_ip}": f"{ip_lim} IP / Akun",
            "{kuota_buat}": buat_akun_short,
            "{buat_akun}": buat_akun_short,
            "{aktif_akun}": aktif_akun_short,
            "{server}": f"{srv_cnt} VPS ({total_acc} Akun Aktif)",
            "{akun_aktif}": str(total_acc),
            "{status_bot}": bot_st,
        }
        for k, v in replacements.items():
            res = res.replace(k, v)
        if "Buat akun" not in res and "Aktif akun" not in res:
            res += (
                f"\n{line_sep}\n"
                f"{b} <b>Buat akun</b>   : {buat_akun_short}\n"
                f"{b} <b>Aktif akun</b>  : {aktif_akun_short}"
            )
        return res

    return (
        f"{th['title']}\n"
        f"{line_sep}\n"
        f"{b} <b>Domain</b>      : <code>{html.escape(cur_domain)}</code>\n"
        f"{b} <b>Lokasi</b>      : {html.escape(DEFAULT_CITY)}\n"
        f"{b} <b>ISP</b>         : {html.escape(DEFAULT_ISP)}\n"
        f"{b} <b>Buat akun</b>   : {buat_akun_short}\n"
        f"{b} <b>Aktif akun</b>  : {aktif_akun_short}\n"
        f"{b} <b>Server</b>      : {srv_cnt} VPS ({total_acc} Akun Aktif)\n"
        f"{b} <b>Status Bot</b>  : {bot_st}\n"
        f"{line_sep}\n"
        "Silakan pilih menu layanan di bawah ini:"
    )

async def send_welcome_screen(msg_or_cb, user_id: int, is_callback: bool = False):
    caption = format_welcome_caption(user_id)
    kb = main_menu_kb(user_id)
    photo_id = get_setting("welcome_photo", "").strip()

    if not is_callback:
        if photo_id:
            try:
                await msg_or_cb.answer_photo(photo=photo_id, caption=caption, parse_mode="HTML", reply_markup=kb)
                return
            except Exception:
                pass
        await msg_or_cb.answer(caption, parse_mode="HTML", reply_markup=kb)
    else:
        cb = msg_or_cb
        if photo_id:
            if cb.message.photo:
                try:
                    await cb.message.edit_caption(caption=caption, parse_mode="HTML", reply_markup=kb)
                    return
                except Exception:
                    pass
            try:
                await cb.message.delete()
            except Exception:
                pass
            await cb.message.answer_photo(photo=photo_id, caption=caption, parse_mode="HTML", reply_markup=kb)
        else:
            if cb.message.photo:
                try:
                    await cb.message.delete()
                except Exception:
                    pass
                await cb.message.answer(caption, parse_mode="HTML", reply_markup=kb)
            else:
                try:
                    await cb.message.edit_text(caption, parse_mode="HTML", reply_markup=kb)
                except Exception:
                    pass

def sanitize_tg_html(text: str) -> str:
    if not text:
        return ""
    return re.sub(r"&(?!(?:amp|lt|gt|quot|#\d+);)", "&amp;", str(text))

async def safe_edit_Basic(cb: CallbackQuery, text: str, reply_markup=None, parse_mode="HTML"):
    if parse_mode == "HTML":
        text = sanitize_tg_html(text)
    if cb.message and cb.message.photo:
        try:
            await cb.message.delete()
        except Exception:
            pass
        await cb.message.answer(text, parse_mode=parse_mode, reply_markup=reply_markup)
    else:
        try:
            await cb.message.edit_text(text, parse_mode=parse_mode, reply_markup=reply_markup)
        except Exception as e:
            if "message is not modified" in str(e).lower():
                try:
                    await cb.answer("✅ Data sudah paling baru!")
                except Exception:
                    pass
            else:
                try:
                    await cb.message.answer(text, parse_mode=parse_mode, reply_markup=reply_markup)
                except Exception:
                    pass

def build_welcome_text(user_id: int) -> str:
    return format_welcome_caption(user_id)

def main_menu_kb(user_id: int):
    th = get_active_theme()
    c_lbl = th["btn_create"]
    t_lbl = th["btn_trial"]
    buttons = [
        [
            InlineKeyboardButton(text=f"{c_lbl} SSH", callback_data="create:ssh:0"),
            InlineKeyboardButton(text=f"{c_lbl} VMess", callback_data="create:vmess:0")
        ],
        [
            InlineKeyboardButton(text=f"{c_lbl} VLESS", callback_data="create:vless:0"),
            InlineKeyboardButton(text=f"{c_lbl} Trojan", callback_data="create:trojan:0")
        ],
        [
            InlineKeyboardButton(text=f"{t_lbl} SSH", callback_data="create:ssh:1"),
            InlineKeyboardButton(text=f"{t_lbl} VMess", callback_data="create:vmess:1")
        ],
        [
            InlineKeyboardButton(text=f"{t_lbl} VLESS", callback_data="create:vless:1"),
            InlineKeyboardButton(text=f"{t_lbl} Trojan", callback_data="create:trojan:1")
        ],
        [
            InlineKeyboardButton(text="🔍 Cek Status Bug / Host ISP", callback_data="bug_scanner_start")
        ],
        [
            InlineKeyboardButton(text="💉 Inject Akun Luar", callback_data="ext_inject_start"),
            InlineKeyboardButton(text="🌐 List Wildcard", callback_data="list_wildcard_menu")
        ],
        [
            InlineKeyboardButton(text="👤 Akun Saya", callback_data="my_accounts"),
            InlineKeyboardButton(text="📊 Status Server", callback_data="server_info")
        ]
    ]
    if user_id == ADMIN_ID:
        buttons.append([InlineKeyboardButton(text="⚙️ Panel Admin", callback_data="admin_home")])
    return InlineKeyboardMarkup(inline_keyboard=buttons)

def admin_menu_kb():
    bot_on = get_setting("bot_status", "1") == "1"
    bot_lbl = "🤖 Status Bot: ON 🟢" if bot_on else "🤖 Status Bot: OFF 🔴"
    heal_on = get_setting("auto_heal_enabled", "1") == "1"
    heal_lbl = "🩺 Auto-Heal: ON 🟢" if heal_on else "🩺 Auto-Heal: OFF 🔴"
    pfx_on = get_setting("prefix_enabled", "1") == "1"
    pfx_val = get_setting("account_prefix", "sunek").strip().strip("-") or "sunek"
    pfx_lbl = f"🏷️ Prefix: ON ({pfx_val}-) 🟢" if pfx_on else "🏷️ Prefix Akun: OFF 🔴"
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="🖥 INFO VPS", callback_data="adm_info_vps"),
            InlineKeyboardButton(text="🔧 SSL & Services", callback_data="adm_ssl_services")
        ],
        [
            InlineKeyboardButton(text=bot_lbl, callback_data="adm_toggle_bot"),
            InlineKeyboardButton(text=heal_lbl, callback_data="adm_autoheal_menu")
        ],
        [
            InlineKeyboardButton(text=pfx_lbl, callback_data="adm_prefix_menu")
        ],
        [
            InlineKeyboardButton(text="🌐 Change Domain VPS", callback_data="adm_chg_domain_menu"),
            InlineKeyboardButton(text="🔄 Reset Limit Semua User", callback_data="adm_reset_all_quotas")
        ],
        [
            InlineKeyboardButton(text="🟢 Cek User Online", callback_data="adm_online"),
            InlineKeyboardButton(text="📊 Auto-Report Login Grup", callback_data="adm_login_rep_menu")
        ],
        [
            InlineKeyboardButton(text="🔓 Unlock Limit IP", callback_data="adm_unlock_list")
        ],
        [
            InlineKeyboardButton(text="👥 Kelola User & ID", callback_data="adm_users"),
            InlineKeyboardButton(text="🗑 Hapus Semua Akun", callback_data="adm_del_all_menu")
        ],
        [
            InlineKeyboardButton(text="🔒 Pengaturan Lock", callback_data="adm_lock_cfg"),
            InlineKeyboardButton(text="⚙️ Durasi, Kuota & Limit Buat", callback_data="adm_limits_cfg")
        ],
        [
            InlineKeyboardButton(text="🌐 SlowDNS & UDP-Custom", callback_data="adm_slowdns_udp")
        ],
        [
            InlineKeyboardButton(text="🖥 Kelola Multi-VPS", callback_data="adm_vps"),
            InlineKeyboardButton(text="🌍 Relay Multi-Negara", callback_data="adm_relays")
        ],
        [
            InlineKeyboardButton(text="🐞 Kelola Preset Bug", callback_data="adm_bugs_menu"),
            InlineKeyboardButton(text="📝 Banner HTML & Bug", callback_data="adm_banner_cfg")
        ],
        [
            InlineKeyboardButton(text="📢 Wajib Join & Set Topic", callback_data="adm_group_cfg"),
            InlineKeyboardButton(text="🖼 Set Welcome (Teks/Foto)", callback_data="adm_welcome_cfg")
        ],
        [
            InlineKeyboardButton(text="🎨 Ganti Tema Bot", callback_data="adm_theme_menu"),
            InlineKeyboardButton(text="📣 Broadcast User", callback_data="adm_broadcast_menu")
        ],
        [
            InlineKeyboardButton(text="📦 Kirim Full Script Portable", callback_data="adm_send_backup"),
            InlineKeyboardButton(text="📋 Log Aktivitas", callback_data="adm_logs")
        ],
        [
            InlineKeyboardButton(text="⬅️ Kembali ke Menu Utama", callback_data="back_home")
        ]
    ])

@router.message(Command("setbuat", "setcreate"))
async def cmd_set_buat(msg: Message):
    record_group_topic(msg)
    if msg.from_user.id != ADMIN_ID:
        return
    cid, tid = str(msg.chat.id), str(msg.message_thread_id or 0)
    set_setting("group_chat_id", cid)
    set_setting("create_topic_id", tid)
    set_setting("notif_create_group", "1")
    await msg.reply(f"✅ <b>Topic Log Buat Akun Disimpan!</b>\n• Group ID: <code>{cid}</code>\n• Topic ID: <code>{tid}</code>", parse_mode="HTML")

@router.message(Command("setlock", "setmultilogin"))
async def cmd_set_lock(msg: Message):
    record_group_topic(msg)
    if msg.from_user.id != ADMIN_ID:
        return
    cid, tid = str(msg.chat.id), str(msg.message_thread_id or 0)
    set_setting("group_chat_id", cid)
    set_setting("group_topic_id", tid)
    await msg.reply(f"🚨 <b>Topic Log Multi-Login Disimpan!</b>\n• Group ID: <code>{cid}</code>\n• Topic ID: <code>{tid}</code>", parse_mode="HTML")

@router.message(Command("id", "getid", "topicid"))
async def cmd_get_id(msg: Message):
    record_group_topic(msg)
    chat_id, thread_id = msg.chat.id, msg.message_thread_id or 0
    kb = None
    if msg.from_user.id == ADMIN_ID and chat_id < 0:
        kb = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="📌 Jadikan Topic Log Buat Akun", callback_data=f"bind_grp:{chat_id}:{thread_id}:create")],
            [InlineKeyboardButton(text="🚨 Jadikan Topic Log Multi-Login", callback_data=f"bind_grp:{chat_id}:{thread_id}:lock")],
            [InlineKeyboardButton(text="✅ Jadikan Topic Semua Notifikasi", callback_data=f"bind_grp:{chat_id}:{thread_id}:all")]
        ])
    await msg.reply(
        f"<b>INFO ID CHAT & TOPIC</b>\n• User ID: <code>{msg.from_user.id}</code>\n• Group ID: <code>{chat_id}</code>\n• Topic ID: <code>{thread_id}</code>",
        parse_mode="HTML", reply_markup=kb
    )

@router.callback_query(F.data.startswith("bind_grp:"))
async def cb_bind_grp(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    _, chat_id_str, thread_id_str, mode = cb.data.split(":")
    set_setting("group_chat_id", chat_id_str)
    if mode in ("all", "lock"):
        set_setting("group_topic_id", thread_id_str)
    if mode in ("all", "create"):
        set_setting("create_topic_id", thread_id_str)
    await cb.answer("✅ Grup & Topic berhasil disimpan!", show_alert=True)
    if cb.message.chat.id > 0:
        await cb_adm_group_cfg(cb)
    else:
        await safe_edit_Basic(cb, f"✅ <b>Topic Ditautkan!</b>\n• Group: <code>{chat_id_str}</code>\n• Topic: <code>{thread_id_str}</code> ({mode.upper()})", parse_mode="HTML")

@router.message(Command("start", "menu"))
async def cmd_start(msg: Message, state: FSMContext):
    record_group_topic(msg)
    await state.clear()
    if msg.chat.id < 0:
        me = await bot.get_me()
        kb = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="💬 Buat Akun di Private Chat (DM)", url=f"https://t.me/{me.username}")]
        ])
        await msg.reply(
            "ℹ️ <b>Grup/Topik ini khusus untuk Notifikasi Sistem.</b>\n"
            "Pembuatan akun tidak dapat dilakukan di dalam grup. Silakan klik tombol di bawah untuk membuat akun melalui Private Chat (DM):",
            parse_mode="HTML",
            reply_markup=kb
        )
        return
    sync_user_profile(msg.from_user)
    allowed, reason = check_user_access(msg.from_user.id)
    if not allowed:
        await msg.answer(reason)
        return
    if not await check_force_join(msg.from_user.id):
        fj_txt, fj_kb = build_force_join_prompt()
        await msg.answer(fj_txt, parse_mode="HTML", reply_markup=fj_kb)
        return
    await send_welcome_screen(msg, msg.from_user.id, is_callback=False)

@router.callback_query(F.data == "back_home")
async def cb_back_home(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    sync_user_profile(cb.from_user)
    allowed, reason = check_user_access(cb.from_user.id)
    if not allowed:
        await cb.answer(reason, show_alert=True)
        return
    await send_welcome_screen(cb, cb.from_user.id, is_callback=True)

@router.callback_query(F.data == "my_accounts")
async def cb_my_accounts(cb: CallbackQuery):
    allowed, reason = check_user_access(cb.from_user.id)
    if not allowed:
        await cb.answer(reason, show_alert=True)
        return
    now = int(time.time())
    with db_conn() as conn:
        rows = conn.execute(
            "SELECT a.*, s.name as srv_name FROM accounts a LEFT JOIN servers s ON a.server_id = s.id WHERE a.user_id=? AND a.expired_at > ? ORDER BY a.id DESC",
            (cb.from_user.id, now)
        ).fetchall()
    if not rows:
        await cb.answer("Anda belum memiliki akun aktif.", show_alert=True)
        return
    lines = ["<b>DAFTAR AKUN SAYA</b>\n────────────────────────────"]
    kb = []
    for r in rows:
        exp_dt = "Unlimited" if r["expired_at"] >= 4000000000 else datetime.fromtimestamp(r["expired_at"]).strftime("%Y-%m-%d %H:%M WIB")
        srv_lbl = r["srv_name"] or "Server Utama"
        if r["locked_until"] > now:
            lock_str = datetime.fromtimestamp(r["locked_until"]).strftime("%H:%M WIB")
            status_lbl = f"🔴 <b>TERKUNCI sampai {lock_str}</b>"
            kb.append([InlineKeyboardButton(text=f"📄 Lihat {r['username']} ({r['protocol'].upper()})", callback_data=f"view_my:{r['id']}")])
        else:
            status_lbl = "🟢 Aktif"
            kb.append([
                InlineKeyboardButton(text=f"📄 {r['username']} ({r['protocol'].upper()})", callback_data=f"view_my:{r['id']}"),
                InlineKeyboardButton(text="🎯 Inject Bug", callback_data=f"inj_menu:{r['id']}"),
                InlineKeyboardButton(text="🗑", callback_data=f"del_my:{r['id']}")
            ])
            if r["protocol"] in ("vmess", "vless", "trojan"):
                kb.append([
                    InlineKeyboardButton(text=f"🔄 Tukar Protokol ({r['username']})", callback_data=f"chg_proto_menu:{r['id']}"),
                    InlineKeyboardButton(text="🌐 Pindah Server", callback_data=f"move_srv_menu:{r['id']}")
                ])
            else:
                kb.append([
                    InlineKeyboardButton(text=f"🌐 Pindah Server ({r['username']})", callback_data=f"move_srv_menu:{r['id']}")
                ])
        lines.append(
            f"• <code>{html.escape(r['username'])}</code> ({r['protocol'].upper()}) — <b>{html.escape(srv_lbl)}</b>\n"
            f"  Status : {status_lbl}\n"
            f"  Limit  : {'Unlimited' if r['ip_limit'] == 0 else str(r['ip_limit']) + ' IP'} | Exp: {exp_dt}"
        )
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Menu Utama", callback_data="back_home")])
    await safe_edit_Basic(cb, "\n".join(lines), parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("view_my:"))
async def cb_view_my_acc(cb: CallbackQuery):
    acc_id = int(cb.data.split(":")[1])
    now = int(time.time())
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()
    out_html, kb = build_account_details_and_kb(acc, srv, back_target="my_accounts")
    lock_note = f"⚠️ <b>Status: TERKUNCI sampai {datetime.fromtimestamp(acc['locked_until']).strftime('%H:%M WIB')}</b>\n\n" if acc["locked_until"] > now else ""
    await safe_edit_Basic(cb, f"{lock_note}{out_html}\n<i>Ketuk teks link atau tombol di bawah untuk menyalin:</i>", parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("cp:"))
async def cb_copy_fallback(cb: CallbackQuery):
    _, acc_id_str, part = cb.data.split(":")
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (int(acc_id_str),)).fetchone()
        if not acc:
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id:
            await cb.answer("Akses ditolak.", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone()
    host, uname, secret = srv["host"], acc["username"], acc["secret"]
    val = secret
    if acc["protocol"] == "vmess":
        if part == "wstls": val = engine.make_vmess_b64(uname, host, 443, secret, "ws", "/vmess", "tls")
        elif part == "wsntls": val = engine.make_vmess_b64(uname, host, 80, secret, "ws", "/vmess", "none")
        elif part == "grpc": val = engine.make_vmess_b64(uname, host, 443, secret, "grpc", "vmess", "tls")
        elif part == "uptls": val = engine.make_vmess_b64(uname, host, 443, secret, "httpupgrade", "/upvmess", "tls")
        elif part == "upntls": val = engine.make_vmess_b64(uname, host, 80, secret, "httpupgrade", "/upvmess", "none")
    await cb.message.answer(f"Ketuk teks di bawah untuk menyalin:\n<code>{html.escape(val)}</code>", parse_mode="HTML")
    await cb.answer("Teks siap disalin!")

@router.callback_query(F.data.startswith("del_my:"))
async def cb_del_my_acc(cb: CallbackQuery):
    acc_id = int(cb.data.split(":")[1])
    now = int(time.time())
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if acc["locked_until"] > now and cb.from_user.id != ADMIN_ID:
            await cb.answer("Akun sedang TERKUNCI dan tidak dapat dihapus sampai masa kunci selesai.", show_alert=True)
            return
        if acc["protocol"] == "ssh":
            engine.delete_ssh_user(acc["username"])
        else:
            engine.remove_xray_user(acc["protocol"], acc["username"])
        conn.execute("DELETE FROM accounts WHERE id=?", (acc_id,))
        conn.commit()
    log_activity("DELETE_USER", f"{acc['username']} dihapus oleh {cb.from_user.id}")
    await cb.answer("Akun berhasil dihapus.", show_alert=True)
    await cb_my_accounts(cb)

@router.callback_query(F.data.startswith("create:"))
async def cb_create_start(cb: CallbackQuery, state: FSMContext):
    if cb.message and cb.message.chat.id < 0:
        await cb.answer("⚠️ Grup ini khusus notifikasi! Silakan buat akun lewat Private Chat (DM) Bot.", show_alert=True)
        return
    sync_user_profile(cb.from_user)
    allowed, reason = check_user_access(cb.from_user.id)
    if not allowed:
        await cb.answer(reason, show_alert=True)
        return
    if not await check_force_join(cb.from_user.id):
        await cb.answer("Wajib join channel/grup terlebih dahulu!", show_alert=True)
        return
    if user_has_locked_account(cb.from_user.id) and cb.from_user.id != ADMIN_ID:
        await cb.answer("Salah satu akun Anda sedang TERKUNCI karena multi-login.", show_alert=True)
        return

    _, proto, is_trial_str = cb.data.split(":")
    is_trial = int(is_trial_str)
    q_ok, q_msg = check_user_create_quota(cb.from_user.id, is_trial)
    if not q_ok:
        await cb.answer(q_msg, show_alert=True)
        return

    with db_conn() as conn:
        servers = conn.execute("SELECT * FROM servers").fetchall()
    if len(servers) > 1:
        kb = [[InlineKeyboardButton(text=f"🖥 {s['name']} ({s['city']})", callback_data=f"pick_srv:{proto}:{is_trial}:{s['id']}")] for s in servers]
        kb.append([InlineKeyboardButton(text="⬅️ Batal", callback_data="back_home")])
        await safe_edit_Basic(cb, "<b>Pilih Lokasi Server VPS:</b>", parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))
        return
    await proceed_server_selection(cb, state, proto, is_trial, servers[0]["id"])

@router.callback_query(F.data.startswith("pick_srv:"))
async def cb_pick_srv(cb: CallbackQuery, state: FSMContext):
    _, proto, is_trial_str, srv_id_str = cb.data.split(":")
    await proceed_server_selection(cb, state, proto, int(is_trial_str), int(srv_id_str))

async def proceed_server_selection(cb: CallbackQuery, state: FSMContext, proto: str, is_trial: int, srv_id: int):
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
        cnt = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (srv_id, int(time.time()))).fetchone()["c"]
    max_u = (srv["max_users"] if srv and "max_users" in srv.keys() and srv["max_users"] else get_int_setting("max_users_per_vps", 100, 1))
    if cnt >= max_u:
        await cb.answer(f"Server penuh ({cnt}/{max_u} akun aktif).", show_alert=True)
        return

    if is_trial == 1:
        await cb.answer("⏳ Membuat akun Trial...")
        uname = apply_account_prefix(f"trial{random.randint(10000, 99999)}")
        with db_conn() as conn:
            while conn.execute("SELECT 1 FROM accounts WHERE username=?", (uname,)).fetchone():
                uname = apply_account_prefix(f"trial{random.randint(10000, 99999)}")
        secret = f"123{random.choice('abcdef')}{random.randint(1, 9)}" if proto == "ssh" else str(uuid.uuid4())
        await finalize_account_creation(cb.message, cb.from_user, srv, proto, uname, secret, is_trial=1, edit_mode=True)
    else:
        await state.update_data(proto=proto, is_trial=0, srv_id=srv_id)
        await state.set_state(FormState.create_username)
        pfx_note = ""
        if get_setting("prefix_enabled", "1") == "1":
            pfx_str = get_setting("account_prefix", "sunek").strip().strip("-") or "sunek"
            pfx_note = f"\n🏷️ <i>Otomatis ditambahkan prefix <code>{html.escape(pfx_str)}-</code> di depan nama akun Anda.</i>"
        await safe_edit_Basic(
            cb,
            f"<b>Buat Akun {proto.upper()}</b>\n────────────────────────────\n"
            f"Masukkan <b>Username / Remarks</b> (huruf/angka, 3-14 karakter):{pfx_note}",
            parse_mode="HTML"
        )

@router.message(FormState.create_username)
async def msg_create_username(msg: Message, state: FSMContext):
    if msg.chat.id < 0:
        return
    raw_in = (msg.text or "").strip()
    clean_check = raw_in.replace("-", "")
    if not clean_check.isalnum() or not (3 <= len(clean_check) <= 14):
        await msg.answer("⚠️ Username harus huruf/angka (3-14 karakter). Silakan coba lagi:")
        return
    uname = apply_account_prefix(raw_in)
    with db_conn() as conn:
        if conn.execute("SELECT 1 FROM accounts WHERE username=?", (uname,)).fetchone():
            await msg.answer(f"⚠️ Username <code>{html.escape(uname)}</code> sudah digunakan, silakan ketik nama yang lain:", parse_mode="HTML")
            return
    data = await state.get_data()
    if data["proto"] == "ssh":
        await state.update_data(username=uname)
        await state.set_state(FormState.create_password)
        await msg.answer(
            f"✅ Username: <code>{html.escape(uname)}</code>\n"
            "🔑 Sekarang masukkan <b>Password</b> untuk akun SSH:",
            parse_mode="HTML"
        )
    else:
        with db_conn() as conn:
            srv = conn.execute("SELECT * FROM servers WHERE id=?", (data["srv_id"],)).fetchone()
        await state.clear()
        await finalize_account_creation(msg, msg.from_user, srv, data["proto"], uname, str(uuid.uuid4()), is_trial=0, edit_mode=False)

@router.message(FormState.create_password)
async def msg_create_password(msg: Message, state: FSMContext):
    passwd = msg.text.strip()
    data = await state.get_data()
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (data["srv_id"],)).fetchone()
    await state.clear()
    await finalize_account_creation(msg, msg.from_user, srv, "ssh", data["username"], passwd, is_trial=0, edit_mode=False)

async def finalize_account_creation(msg_obj: Message, tg_user, srv, proto: str, uname: str, secret: str, is_trial: int, edit_mode: bool = False):
    try:
        user_id = tg_user.id
        now = int(time.time())
        ip_limit = get_int_setting("default_ip_limit", 2, 1)
        quota_gb = get_int_setting("default_quota_gb", 50, 0)
        speed_mbps = get_int_setting("default_speed_mbps", 0, 0)

        if is_trial:
            t_min = get_int_setting("trial_minutes", 30, 1)
            exp_ts = now + (t_min * 60)
            exp_display = f"{t_min} Menit"
            exp_ssh_date = (datetime.now() + timedelta(days=2)).strftime("%Y-%m-%d")
        else:
            days = get_int_setting("default_days", 7, 1)
            exp_ts = now + (days * 86400)
            exp_display = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")
            exp_ssh_date = exp_display

        if srv["is_local"] == 1:
            if proto == "ssh":
                engine.create_ssh_user(uname, secret, exp_ssh_date)
            else:
                engine.add_xray_user(proto, uname, secret)
        else:
            await asyncio.to_thread(engine.create_remote_account, srv, proto, uname, secret, exp_ssh_date)

        with db_conn() as conn:
            try:
                cur = conn.execute(
                    """INSERT INTO accounts (user_id, server_id, protocol, username, secret, ip_limit, quota_gb, speed_mbps, created_at, expired_at, is_trial)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (user_id, srv["id"], proto, uname, secret, ip_limit, quota_gb, speed_mbps, now, exp_ts, is_trial)
                )
            except sqlite3.IntegrityError:
                # Race: username sudah diambil proses lain (kolom username UNIQUE).
                conn.rollback()
                try:
                    engine.remove_account_from_server(srv, proto, uname)
                except Exception:
                    pass
                log_activity("CREATE_ACCOUNT_FAILED", f"{proto.upper()} {uname} gagal: username sudah dipakai (race)")
                fail_txt = f"❌ Gagal membuat akun: username <code>{html.escape(mask_str(uname))}</code> sudah dipakai. Silakan coba lagi dengan nama lain."
                if edit_mode:
                    try:
                        await msg_obj.edit_text(fail_txt, parse_mode="HTML")
                    except Exception:
                        await msg_obj.answer(fail_txt, parse_mode="HTML")
                else:
                    await msg_obj.answer(fail_txt, parse_mode="HTML")
                return
            acc_id = cur.lastrowid
            conn.execute("INSERT INTO create_history (user_id, username, protocol, is_trial, created_at) VALUES (?, ?, ?, ?, ?)", (user_id, uname, proto, is_trial, now))
            conn.commit()
            acc_row = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()

        log_activity("CREATE_ACCOUNT", f"{proto.upper()} {uname} ({'Trial' if is_trial else 'Reguler'}) dibuat oleh {user_id}")
        out_html, kb = build_account_details_and_kb(acc_row, srv, back_target="back_home")
        text_msg = f"{out_html}\n<i>Ketuk teks link atau tombol di bawah untuk menyalin cepat:</i>"
        if edit_mode:
            try:
                await msg_obj.edit_text(text_msg, parse_mode="HTML", reply_markup=kb)
            except Exception:
                await msg_obj.answer(text_msg, parse_mode="HTML", reply_markup=kb)
        else:
            await msg_obj.answer(text_msg, parse_mode="HTML", reply_markup=kb)

        if get_setting("notif_create_group", "1") == "1":
            grp_id = get_setting("group_chat_id", "").strip()
            c_topic = get_int_setting("create_topic_id", 0, 0) or get_int_setting("group_topic_id", 0, 0)
            if grp_id:
                try:
                    me = await bot.get_me()
                    bot_uname = me.username or "Bot"
                    bot_link = f"https://t.me/{bot_uname}"
                except Exception:
                    bot_uname = "BotVPN"
                    bot_link = "https://t.me/"
                u_tag = f"@{tg_user.username}" if tg_user.username else "-"
                tipe_lbl = "🐒 Trial" if is_trial else "🦆 Reguler"
                srv_isp = srv["isp"] if ("isp" in srv.keys() and srv["isp"]) else DEFAULT_ISP
                grp_msg = (
                    "✨ <b>AKUN BARU DIBUAT</b> ✨\n"
                    "────────────────────────────\n"
                    f"👤 <b>Pemilik</b>  : {html.escape(tg_user.first_name or 'User')} ({html.escape(u_tag)})\n"
                    f"🆔 <b>User ID</b>  : <code>{user_id}</code>\n"
                    f"⚡ <b>Protokol</b> : <b>{proto.upper()}</b> ({tipe_lbl})\n"
                    f"🔑 <b>Username</b> : <code>{html.escape(mask_str(uname))}</code>\n"
                    f"🌐 <b>Server</b>   : <code>{html.escape(srv['host'])}</code>\n"
                    f"🏢 <b>ISP</b>      : {html.escape(srv_isp)}\n"
                    f"⏳ <b>Expired</b>  : <b>{html.escape(exp_display)}</b>\n"
                    "────────────────────────────\n"
                    f"🤖 <b>Buat Akun Gratis:</b> <a href=\"{bot_link}\">@{html.escape(bot_uname)}</a>"
                )
                kwargs = {
                    "chat_id": int(grp_id),
                    "text": grp_msg,
                    "parse_mode": "HTML",
                    "disable_web_page_preview": True
                }
                if c_topic > 0:
                    kwargs["message_thread_id"] = c_topic
                try:
                    await bot.send_message(**kwargs)
                except Exception:
                    pass
    except Exception as e:
        await msg_obj.answer(f"❌ Gagal membuat akun: <code>{html.escape(str(e))}</code>", parse_mode="HTML")

@router.callback_query(F.data == "admin_home")
async def cb_admin_home(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()
    bot_st = "🟢 ON (Publik)" if get_setting("bot_status", "1") == "1" else "🔴 OFF (Maintenance)"
    c_max = get_int_setting("user_create_max", 1, 0)
    c_days = get_int_setting("user_create_days", 3, 1)
    txt = (
        "<b>PANEL ADMIN CONTROL</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Domain Utama</b> : <code>{html.escape(DEFAULT_DOMAIN)}</code>\n"
        f"• <b>Status Bot</b>   : {bot_st}\n"
        f"• <b>Limit Buat</b>   : {c_max}x dalam {c_days} Hari\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Silakan pilih menu pengelolaan atau klik <b>🖥 INFO VPS</b>:"
    )
    try:
        await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=admin_menu_kb())
    except Exception:
        await cb.answer()

@router.callback_query(F.data == "adm_info_vps")
async def cb_adm_info_vps(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    txt = build_admin_dashboard_text()
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="🔄 Refresh INFO VPS", callback_data="adm_info_vps"),
            InlineKeyboardButton(text="🔧 SSL & Services", callback_data="adm_ssl_services")
        ],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    try:
        await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)
    except Exception:
        await cb.answer("✅ Data INFO VPS sudah paling baru!")

@router.callback_query(F.data == "adm_ssl_services")
async def cb_adm_ssl_services(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    st = engine.get_dashboard_stats()
    txt = (
        "<b>MANAJEMEN SSL & SERVICES UTAMA</b>\n━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Xray-Core</b>  : {st['xray_st']}\n• <b>OpenSSH</b>    : {st['ssh_st']}\n"
        f"• <b>Dropbear</b>   : {st['db_st']}\n• <b>Proxy/WS</b>   : {st['hap_st']}\n"
        f"• <b>Nginx</b>      : {st['ngx_st']}\n━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Status SSL</b> : {st['ssl_st']}\n• <b>Exp SSL</b>    : <code>{html.escape(st['ssl_exp'])}</code>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔁 Restart Xray", callback_data="svc_act:xray"), InlineKeyboardButton(text="🔁 Restart Nginx", callback_data="svc_act:nginx")],
        [InlineKeyboardButton(text="🔁 Restart Dropbear", callback_data="svc_act:dropbear"), InlineKeyboardButton(text="🔁 Restart SSH & WS", callback_data="svc_act:ssh_ws")],
        [InlineKeyboardButton(text="⚡ Restart Semua Service", callback_data="svc_act:all")],
        [InlineKeyboardButton(text="🔐 Perbarui / Renew SSL", callback_data="svc_act:renew_ssl")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "adm_slowdns_udp")
async def cb_adm_slowdns_udp(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    def _slowdns_info():
        pub = "-"
        try:
            with open("/etc/slowdns/server.pub") as f:
                pub = f.read().strip()
        except Exception:
            pass
        return pub
    pub = await asyncio.to_thread(_slowdns_info)
    def _stat(name):
        return engine.run_cmd(f"systemctl is-active {name}").strip() or "dead"
    s_sd = await asyncio.to_thread(_stat, "slowdns")
    s_uc = await asyncio.to_thread(_stat, "udp-custom")
    txt = (
        "<b>MANAJEMEN SlowDNS & UDP-Custom</b>\n━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>SlowDNS (dnstt)</b>  : {s_sd}\n"
        f"• <b>UDP-Custom</b>       : {s_uc}\n"
        f"• <b>NS</b>              : <code>ns.{html.escape(DEFAULT_DOMAIN)}</code>\n"
        f"• <b>SlowDNS Port</b>    : <code>53, 5300</code>\n"
        f"• <b>UDP-Custom</b>      : <code>1-65535</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<b>PUBLIC KEY</b>:\n<code>{html.escape(pub)}</code>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔑 Generate Public Key Baru", callback_data="sd_act:regen")],
        [InlineKeyboardButton(text="🌐 Regenerate Unit NS (Domain Baru)", callback_data="sd_act:regen_ns")],
        [InlineKeyboardButton(text="🔁 Restart SlowDNS", callback_data="sd_act:restart_sd")],
        [InlineKeyboardButton(text="🔁 Restart UDP-Custom", callback_data="sd_act:restart_uc")],
        [InlineKeyboardButton(text="🧹 Reset iptables & Restart Semua", callback_data="sd_act:restart_all")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "sd_act:regen")
async def cb_sd_regen(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    await cb.answer("🔑 Generate key baru...", show_alert=False)
    def _regen():
        import os as _os
        _os.system("rm -f /etc/slowdns/server.key /etc/slowdns/server.pub")
        _os.system("/usr/local/bin/dnstt-server -gen-key -privkey-file /etc/slowdns/server.key -pubkey-file /etc/slowdns/server.pub")
        _os.system("chmod 600 /etc/slowdns/server.key")
        _os.system("systemctl restart slowdns")
        pub = "-"
        try:
            with open("/etc/slowdns/server.pub") as f:
                pub = f.read().strip()
        except Exception:
            pass
        return pub
    pub = await asyncio.to_thread(_regen)
    await cb.answer(f"✅ Public key baru dibuat & slowdns di-restart.", show_alert=False)
    # Re-render menu dengan key baru
    fake_cb = cb
    await cb_adm_slowdns_udp(fake_cb)

@router.callback_query(F.data.in_({"sd_act:restart_sd", "sd_act:restart_uc", "sd_act:restart_all"}))
async def cb_sd_restart(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    def _do():
        if act == "restart_sd":
            engine.run_cmd("systemctl restart slowdns")
            msg = "🔁 slowdns di-restart."
        elif act == "restart_uc":
            engine.run_cmd("systemctl restart udp-custom")
            msg = "🔁 udp-custom di-restart."
        else:
            engine.run_cmd("/etc/iptables/apply-slowdns-udp.sh")
            engine.run_cmd("systemctl restart slowdns udp-custom iptables-restore")
            msg = "🧹 iptables di-reset & slowdns+udp-custom+iptables-restore di-restart."
        return msg
    msg = await asyncio.to_thread(_do)
    await cb.answer(msg, show_alert=False)

@router.callback_query(F.data == "sd_act:regen_ns")
async def cb_sd_regenservice(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    def _regen():
        # Regenerate slowdns.service dari DOMAIN terkini di config.env, lalu restart
        dom = DEFAULT_DOMAIN
        unit = (
            "[Unit]\nDescription=SlowDNS dnstt Server\nAfter=network.target\n\n"
            "[Service]\n"
            f"ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file /etc/slowdns/server.key ns.{dom} 127.0.0.1:90\n"
            "Restart=on-failure\nRestartSec=3\n\n"
            "[Install]\nWantedBy=multi-user.target\n"
        )
        with open("/etc/systemd/system/slowdns.service", "w") as f:
            f.write(unit)
        os.system("systemctl daemon-reload")
        os.system("systemctl restart slowdns")
        return dom
    dom = await asyncio.to_thread(_regen)
    await cb.answer(f"✅ slowdns.service di-regenerate untuk ns.{dom} & di-restart.", show_alert=False)

@router.callback_query(F.data.startswith("svc_act:"))
async def cb_svc_act(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    if act == "xray": engine.run_cmd("systemctl restart xray")
    elif act == "nginx": engine.run_cmd("systemctl restart nginx")
    elif act == "dropbear": engine.run_cmd("systemctl restart dropbear")
    elif act == "ssh_ws": engine.run_cmd("systemctl restart ssh vpn-ws-bridge vpn-proto-daemons")
    elif act == "all": await asyncio.to_thread(engine.run_cmd, "systemctl restart dropbear ssh xray vpn-ws-bridge vpn-proto-daemons nginx")
    elif act == "renew_ssl":
        await asyncio.to_thread(engine.run_cmd, f"certbot renew --force-renewal >/dev/null 2>&1 && cp -f /etc/letsencrypt/live/{DEFAULT_DOMAIN}/fullchain.pem /etc/xray/certs/fullchain.pem && cp -f /etc/letsencrypt/live/{DEFAULT_DOMAIN}/privkey.pem /etc/xray/certs/privkey.pem && systemctl restart nginx xray")
    await cb.answer("✅ Berhasil dijalankan!", show_alert=True)
    await cb_adm_ssl_services(cb)

@router.callback_query(F.data == "adm_toggle_bot")
async def cb_adm_toggle_bot(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    new_val = "0" if get_setting("bot_status", "1") == "1" else "1"
    set_setting("bot_status", new_val)
    await cb.answer(f"Status Bot: {'ON' if new_val == '1' else 'OFF (Maintenance)'}", show_alert=True)
    await cb_admin_home(cb, state)

@router.callback_query(F.data == "adm_online")
async def cb_adm_online(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    now = int(time.time())
    active_map = engine.scan_active_sessions()
    with db_conn() as conn:
        for acc in conn.execute("SELECT * FROM accounts WHERE expired_at > ?", (now,)).fetchall():
            uname = acc["username"]
            if uname in active_map:
                ips = sorted(list(active_map[uname]["ips"]))
                conn.execute("UPDATE accounts SET last_ips=?, active_sessions=? WHERE id=?", (",".join(ips), active_map[uname]["sessions"], acc["id"]))
            else:
                conn.execute("UPDATE accounts SET active_sessions=0 WHERE id=?", (acc["id"],))
        conn.commit()
        rows = conn.execute("SELECT * FROM accounts WHERE expired_at > ? ORDER BY protocol, username", (now,)).fetchall()

    by_proto = {"ssh": [], "vmess": [], "vless": [], "trojan": []}
    total_online = 0
    for r in rows:
        ips = [x for x in r["last_ips"].split(",") if x]
        sess = r["active_sessions"]
        locked_badge = " 🔴[TERKUNCI]" if r["locked_until"] > now else ""
        if sess > 0 or r["locked_until"] > now:
            if sess > 0: total_online += 1
            last_ip = ips[-1] if ips else "-"
            by_proto.setdefault(r["protocol"], []).append(
                f"  • <code>{html.escape(r['username'])}</code> | IP: <b>{len(ips)}/{r['ip_limit']}</b> | Sesi: {sess} | Last: <code>{html.escape(last_ip)}</code>{locked_badge}"
            )
    text_lines = [f"<b>CEK USER ONLINE (Total: {total_online})</b>\n────────────────────────────"]
    for p in ("ssh", "vmess", "vless", "trojan"):
        items = by_proto.get(p, [])
        text_lines.append(f"• <b>{p.upper()} ({len(items)})</b>:")
        text_lines.extend(items if items else ["  <i>Tidak ada sesi aktif</i>"])
        text_lines.append("")
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔄 Refresh User Online", callback_data="adm_online")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, "\n".join(text_lines), parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "adm_del_all_menu")
async def cb_adm_del_all_menu(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    with db_conn() as conn:
        tot = conn.execute("SELECT COUNT(*) as c FROM accounts").fetchone()["c"]
        trl = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE is_trial=1").fetchone()["c"]
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚠️ Hapus SEMUA Akun ({tot} Akun)", callback_data="confirm_del_all:all")],
        [InlineKeyboardButton(text=f"🧹 Hapus Semua Akun Trial ({trl} Akun)", callback_data="confirm_del_all:trial")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, f"<b>HAPUS SEMUA AKUN</b>\n• Total Akun: <b>{tot}</b>\n• Akun Trial: <b>{trl}</b>", parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("confirm_del_all:"))
async def cb_confirm_del_all(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    mode = cb.data.split(":")[1]
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM accounts WHERE is_trial=1" if mode == "trial" else "SELECT * FROM accounts").fetchall()
        xray_names = set()
        for r in rows:
            if r["protocol"] == "ssh": engine.delete_ssh_user(r["username"])
            else: xray_names.add(r["username"])
        if mode == "trial":
            if xray_names: engine.clear_all_xray_users(only_usernames=xray_names)
            conn.execute("DELETE FROM accounts WHERE is_trial=1")
        else:
            engine.clear_all_xray_users(only_usernames=None)
            conn.execute("DELETE FROM accounts")
        conn.commit()
    await cb.answer(f"✅ Berhasil menghapus {len(rows)} akun!", show_alert=True)
    await cb_admin_home(cb, state)


























async def sync_unlimited_to_all_accounts(mode_key: str):
    now = int(time.time())
    with db_conn() as conn:
        srvs = {s["id"]: s for s in conn.execute("SELECT * FROM servers").fetchall()}
        if mode_key == "default_ip_limit":
            new_lim = get_int_setting("default_ip_limit", 0, 0)
            conn.execute(
                "UPDATE accounts SET ip_limit=?, locked_until=0, strike_count=0, violation_level=0, active_sessions=0 WHERE expired_at > ?",
                (new_lim, now)
            )
            conn.commit()
            accs = conn.execute("SELECT * FROM accounts WHERE expired_at > ?", (now,)).fetchall()
            for a in accs:
                srv = srvs.get(a["server_id"])
                await asyncio.to_thread(engine.set_remote_or_local_lock, srv, a["protocol"], a["username"], a["secret"], False)
        elif mode_key == "default_days":
            new_days = get_int_setting("default_days", 0, 0)
            if new_days <= 0:
                conn.execute("UPDATE accounts SET expired_at=4102444800 WHERE is_trial=0 AND expired_at > ?", (now,))
                conn.commit()
                accs = conn.execute("SELECT * FROM accounts WHERE is_trial=0 AND protocol='ssh' AND expired_at > ?", (now,)).fetchall()
                for a in accs:
                    srv = srvs.get(a["server_id"])
                    await asyncio.to_thread(engine.set_remote_or_local_lock, srv, "ssh", a["username"], a["secret"], False)


@router.callback_query(F.data.startswith("quick_unl:"))
async def cb_quick_unlimited(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    key = cb.data.split(":")[1]
    set_setting(key, "0")
    await cb.answer("⏳ Menyinkronkan pengaturan Unlimited ke seluruh akun & server...")
    await sync_unlimited_to_all_accounts(key)
    if key == "default_ip_limit":
        await cb.message.answer("✅ <b>Limit IP berhasil diatur ke ♾ Unlimited (0)!</b>\nSeluruh akun aktif telah disinkronkan dan dibebaskan dari kunci Multi-Login.", parse_mode="HTML")
    elif key == "default_days":
        await cb.message.answer("✅ <b>Masa Aktif Reguler berhasil diatur ke ♾ Unlimited (Lifetime)!</b>\nSeluruh akun reguler yang aktif juga telah diperbarui ke Unlimited.", parse_mode="HTML")
    await cb_adm_limits_cfg(cb, state)





async def msg_set_cfg(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    key = data["cfg_key"]
    raw_txt = (msg.text or "").strip().lower()
    if raw_txt in ("unlimited", "unl", "0", "inf"):
        val_str = "0"
    else:
        m = re.search(r"\d+", raw_txt)
        val_str = m.group(0) if m else "0"

    set_setting(key, val_str)
    if key == "default_ip_limit":
        with db_conn() as conn:
            conn.execute("UPDATE accounts SET ip_limit=? WHERE expired_at > ?", (int(val_str), int(time.time())))
            conn.commit()
    elif key == "default_speed_mbps":
        engine.apply_global_speed_limit(int(val_str))
    await state.clear()
    disp_val = "♾ Unlimited (0)" if val_str == "0" and key in ("default_days", "default_ip_limit", "default_quota_gb", "default_speed_mbps", "user_create_max") else val_str
    await msg.answer(f"✅ Pengaturan <code>{key}</code> berhasil disimpan menjadi: <b>{disp_val}</b>", parse_mode="HTML", reply_markup=admin_menu_kb())











@router.callback_query(F.data == "do_unlock_all")
async def cb_do_unlock_all(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    now = int(time.time())
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM accounts WHERE locked_until > ? AND expired_at > ?", (now, now)).fetchall()
        srvs = {s["id"]: s for s in conn.execute("SELECT * FROM servers").fetchall()}

    if not rows:
        await cb.answer("Tidak ada akun yang terkunci.", show_alert=True)
        return

    await cb.answer(f"⏳ Membuka kunci {len(rows)} akun...")
    for acc in rows:
        srv = srvs.get(acc["server_id"])
        await asyncio.to_thread(
            engine.set_remote_or_local_lock,
            srv, acc["protocol"], acc["username"], acc["secret"], False
        )
        try:
            await bot.send_message(
                acc["user_id"],
                f"🔓 <b>AKUN DIBUKA OLEH ADMIN</b>\n"
                "────────────────────────────\n"
                f"Akun <code>{html.escape(acc['username'])}</code> ({acc['protocol'].upper()}) telah di-unlock dan siap digunakan kembali!",
                parse_mode="HTML"
            )
        except Exception:
            pass

    with db_conn() as conn:
        conn.execute("UPDATE accounts SET locked_until=0, strike_count=0, violation_level=0, active_sessions=0, last_ips='' WHERE locked_until > 0")
        conn.commit()

    log_activity("MANUAL_UNLOCK_ALL", f"Admin membuka semua ({len(rows)}) akun terkunci")
    await cb_adm_unlock_list(cb)

@router.callback_query(F.data == "adm_resync_all_auth")
async def cb_adm_resync_all_auth(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    now = int(time.time())
    await cb.answer("⏳ Menyinkronkan ulang seluruh akun aktif ke sistem VPS...")
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM accounts WHERE expired_at > ? AND locked_until <= ?", (now, now)).fetchall()
        srvs = {s["id"]: s for s in conn.execute("SELECT * FROM servers").fetchall()}

    for acc in rows:
        srv = srvs.get(acc["server_id"])
        await asyncio.to_thread(
            engine.set_remote_or_local_lock,
            srv, acc["protocol"], acc["username"], acc["secret"], False
        )
    await cb.answer(f"✅ {len(rows)} akun aktif berhasil disinkronkan & dipulihkan!", show_alert=True)
    await cb_adm_unlock_list(cb)

@router.callback_query(F.data == "adm_users")
async def cb_adm_users(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    with db_conn() as conn:
        tot_u = conn.execute("SELECT COUNT(*) as c FROM users").fetchone()["c"]
        ban_u = conn.execute("SELECT COUNT(*) as c FROM users WHERE is_banned=1").fetchone()["c"]
        recent_u = conn.execute("SELECT * FROM users ORDER BY joined_at DESC LIMIT 10").fetchall()
    kb = [[InlineKeyboardButton(text="🔍 Cari ID / Username", callback_data="adm_find_user"), InlineKeyboardButton(text="🔄 Reset Limit Semua User", callback_data="adm_reset_all_quotas")]]
    for u in recent_u:
        st_icon = "🔴" if u["is_banned"] == 1 else "🟢"
        uname_str = f"@{u['username']}" if u["username"] else u["first_name"]
        kb.append([InlineKeyboardButton(text=f"{st_icon} {uname_str} (ID: {u['user_id']})", callback_data=f"adm_uview:{u['user_id']}")])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, f"<b>KELOLA USER & ID</b>\n• Total User: <b>{tot_u}</b> (Banned: <b>{ban_u}</b>)", parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data == "adm_reset_all_quotas")
async def cb_adm_reset_all_quotas(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    with db_conn() as conn:
        conn.execute("DELETE FROM create_history")
        conn.commit()
    await cb.answer("✅ Limit semua user berhasil di-reset!", show_alert=True)
    await cb_adm_users(cb, state)

@router.callback_query(F.data == "adm_find_user")
async def cb_adm_find_user(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.set_state(FormState.admin_search_user)
    await safe_edit_Basic(cb, "🔍 Masukkan <b>ID Telegram</b> atau <b>Username</b>:", parse_mode="HTML")

@router.message(FormState.admin_search_user)
async def msg_adm_search_user(msg: Message, state: FSMContext):
    q = msg.text.strip().lstrip("@")
    await state.clear()
    with db_conn() as conn:
        if q.isdigit():
            u = conn.execute("SELECT * FROM users WHERE user_id=?", (int(q),)).fetchone()
            if not u:
                conn.execute("INSERT INTO users (user_id, username, first_name, is_banned, custom_max_create, joined_at) VALUES (?, '', 'User Manual', 0, -1, ?)", (int(q), int(time.time())))
                conn.commit()
                u = conn.execute("SELECT * FROM users WHERE user_id=?", (int(q),)).fetchone()
        else:
            u = conn.execute("SELECT * FROM users WHERE LOWER(username)=LOWER(?)", (q,)).fetchone()
    if not u:
        await msg.answer("❌ User tidak ditemukan.", reply_markup=admin_menu_kb())
        return
    txt, kb = render_user_manage_detail(u["user_id"])
    await msg.answer(txt, parse_mode="HTML", reply_markup=kb)

def render_user_manage_detail(target_uid: int):
    now = int(time.time())
    u_days = get_int_setting("user_create_days", 3, 1)
    with db_conn() as conn:
        u = conn.execute("SELECT * FROM users WHERE user_id=?", (target_uid,)).fetchone()
        accs = conn.execute("SELECT * FROM accounts WHERE user_id=? AND expired_at > ?", (target_uid, now)).fetchall()
        hist_cnt = conn.execute("SELECT COUNT(*) as c FROM create_history WHERE user_id=? AND is_trial=0 AND created_at >= ?", (target_uid, now - u_days * 86400)).fetchone()["c"]
    quota_lbl = f"{u['custom_max_create']}x (Khusus)" if u["custom_max_create"] >= 0 else f"{get_int_setting('user_create_max', 1, 0)}x (Default)"
    st_lbl = "🔴 BANNED" if u["is_banned"] == 1 else "🟢 AKTIF"
    acc_list_str = "\n".join([f"  • <code>{html.escape(a['username'])}</code> ({a['protocol'].upper()})" for a in accs]) or "  <i>Tidak ada akun aktif</i>"
    txt = (
        f"<b>DETAIL USER ID:</b> <code>{target_uid}</code>\n"
        f"• Nama: {html.escape(u['first_name'] or '-')} (@{html.escape(u['username'] or '-')})\n"
        f"• Status: <b>{st_lbl}</b> | Kuota Buat: {hist_cnt} dari {quota_lbl} / {u_days} Hari\n"
        f"<b>Akun Aktif ({len(accs)}):</b>\n{acc_list_str}"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔄 Reset Limit Buat", callback_data=f"uact:resetq:{target_uid}"), InlineKeyboardButton(text="🎯 Set Kuota Khusus", callback_data=f"uact:setq:{target_uid}")],
        [InlineKeyboardButton(text="✅ Unban User" if u["is_banned"] == 1 else "🚫 Ban User", callback_data=f"uact:toggleban:{target_uid}"), InlineKeyboardButton(text="🗑 Hapus Akun User", callback_data=f"uact:delaccs:{target_uid}")],
        [InlineKeyboardButton(text="⬅️ Kembali", callback_data="adm_users")]
    ])
    return txt, kb

@router.callback_query(F.data.startswith("adm_uview:"))
async def cb_adm_uview(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    txt, kb = render_user_manage_detail(int(cb.data.split(":")[1]))
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("uact:"))
async def cb_uact_handler(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID: return
    _, action, uid_str = cb.data.split(":")
    uid = int(uid_str)
    if action == "resetq":
        with db_conn() as conn:
            conn.execute("DELETE FROM create_history WHERE user_id=?", (uid,))
            conn.commit()
        await cb.answer("✅ Limit di-reset!", show_alert=True)
    elif action == "toggleban":
        with db_conn() as conn:
            u = conn.execute("SELECT is_banned FROM users WHERE user_id=?", (uid,)).fetchone()
            conn.execute("UPDATE users SET is_banned=? WHERE user_id=?", (0 if (u and u["is_banned"] == 1) else 1, uid))
            conn.commit()
        await cb.answer("✅ Status diperbarui!", show_alert=True)
    elif action == "delaccs":
        with db_conn() as conn:
            rows = conn.execute("SELECT * FROM accounts WHERE user_id=?", (uid,)).fetchall()
            for r in rows:
                if r["protocol"] == "ssh": engine.delete_ssh_user(r["username"])
                else: engine.remove_xray_user(r["protocol"], r["username"])
            conn.execute("DELETE FROM accounts WHERE user_id=?", (uid,))
            conn.commit()
        await cb.answer(f"✅ {len(rows)} akun dihapus!", show_alert=True)
    elif action == "setq":
        await state.update_data(target_uid=uid)
        await state.set_state(FormState.admin_set_user_quota)
        await safe_edit_Basic(cb, f"Masukkan kuota buat akun untuk ID <code>{uid}</code> (0 = Unlimited, -1 = Default):", parse_mode="HTML")
        return
    txt, kb = render_user_manage_detail(uid)
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.message(FormState.admin_set_user_quota)
async def msg_adm_set_user_quota(msg: Message, state: FSMContext):
    uid = (await state.get_data())["target_uid"]
    m = re.search(r"-?\d+", msg.text.strip())
    val = int(m.group(0)) if m else -1
    with db_conn() as conn:
        conn.execute("UPDATE users SET custom_max_create=? WHERE user_id=?", (val, uid))
        conn.commit()
    await state.clear()
    txt, kb = render_user_manage_detail(uid)
    await msg.answer(txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "adm_send_backup")
async def cb_adm_send_backup(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    await cb.answer("📦 Mengirim Full Script Portable ke chat Anda...", show_alert=True)
    subprocess.Popen(["/etc/vpn-bot/venv/bin/python", "/etc/vpn-bot/send_backup.py", "Request Manual dari Panel Admin"])

@router.callback_query(F.data == "adm_unlock_list")
async def cb_adm_unlock_list(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    now = int(time.time())
    with db_conn() as conn:
        locked = conn.execute("SELECT * FROM accounts WHERE locked_until > ?", (now,)).fetchall()
    if not locked:
        await cb.answer("Tidak ada akun terkunci.", show_alert=True)
        return
    lines = ["<b>DAFTAR AKUN TERKUNCI</b>\n────────────────────────────"]
    kb = []
    for r in locked:
        rem_min = max(1, int((r["locked_until"] - now) / 60))
        lines.append(f"• <code>{html.escape(r['username'])}</code> ({r['protocol'].upper()}) — Sisa: <b>{rem_min}m</b> (IP: <code>{html.escape(r['last_ips'])}</code>)")
        kb.append([InlineKeyboardButton(text=f"🔓 Unlock {r['username']}", callback_data=f"do_unlock:{r['id']}")])
    kb.append([InlineKeyboardButton(text="🔓 Unlock Semua", callback_data="do_unlock:all")])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali", callback_data="admin_home")])
    await safe_edit_Basic(cb, "\n".join(lines), parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("do_unlock:"))
async def cb_do_unlock(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    target = cb.data.split(":")[1]
    now = int(time.time())
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM accounts WHERE locked_until > ?", (now,)).fetchall() if target == "all" else conn.execute("SELECT * FROM accounts WHERE id=?", (int(target),)).fetchall()
        for r in rows:
            exp_date_str = datetime.fromtimestamp(r["expired_at"]).strftime("%Y-%m-%d")
            if r["protocol"] == "ssh": engine.unlock_ssh_user(r["username"], exp_date_str)
            else: engine.add_xray_user(r["protocol"], r["username"], r["secret"])
            conn.execute("UPDATE accounts SET locked_until=0, strike_count=0, active_sessions=0, last_ips='' WHERE id=?", (r["id"],))
        conn.commit()
    await cb.answer("Akun berhasil di-unlock.", show_alert=True)
    await cb_admin_home(cb, None)

@router.callback_query(F.data == "adm_lock_cfg")
async def cb_adm_lock_cfg(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    en = "ON" if get_setting("lock_enabled") == "1" else "OFF"
    tr = "ON" if get_setting("lock_tiered") == "1" else "OFF"
    txt = (
        "<b>PENGATURAN LOCK MULTI-LOGIN</b>\n────────────────────────────\n"
        f"• Auto-Lock: <b>{en}</b> | Bertingkat: <b>{tr}</b>\n"
        f"• Durasi Lock: <b>{get_int_setting('lock_duration_min', 5, 1)} Menit</b> | Strike: <b>{get_int_setting('lock_strikes', 1, 1)}x</b>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"Auto-Lock ({en})", callback_data="toggle_cfg:lock_enabled"), InlineKeyboardButton(text=f"Bertingkat ({tr})", callback_data="toggle_cfg:lock_tiered")],
        [InlineKeyboardButton(text="Ubah Durasi Lock (Menit)", callback_data="set_cfg:lock_duration_min"), InlineKeyboardButton(text="Ubah Jumlah Strike", callback_data="set_cfg:lock_strikes")],
        [InlineKeyboardButton(text="⬅️ Kembali", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "adm_limits_cfg")
async def cb_adm_limits_cfg(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    txt = (
        "<b>DURASI, KUOTA, SPEED & LIMIT BUAT</b>\n────────────────────────────\n"
        f"• Masa Aktif Reguler : <b>{get_int_setting('default_days', 7, 1)} Hari</b>\n"
        f"• Durasi Trial : <b>{get_int_setting('trial_minutes', 30, 1)} Menit</b>\n"
        f"• Limit Buat Akun : <b>{get_int_setting('user_create_max', 1, 0)}x dalam {get_int_setting('user_create_days', 3, 1)} Hari</b>\n"
        f"• Limit Buat Trial : <b>{get_int_setting('trial_create_max', 3, 0)}x / Hari</b>\n"
        f"• Limit IP : <b>{get_int_setting('default_ip_limit', 2, 1)} IP</b> | Kuota: <b>{get_int_setting('default_quota_gb', 50, 0)} GB</b>\n"
        f"• Speed Limit : <b>{get_int_setting('default_speed_mbps', 0, 0)} Mbps</b> | Max User: <b>{get_int_setting('max_users_per_vps', 100, 1)}</b>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📅 Masa Aktif (Hari)", callback_data="set_cfg:default_days"), InlineKeyboardButton(text="⏱ Durasi Trial (Menit)", callback_data="set_cfg:trial_minutes")],
        [InlineKeyboardButton(text="🔢 Max Buat Akun", callback_data="set_cfg:user_create_max"), InlineKeyboardButton(text="📆 Rentang Hari Buat", callback_data="set_cfg:user_create_days")],
        [InlineKeyboardButton(text="🎁 Max Trial / Hari", callback_data="set_cfg:trial_create_max"), InlineKeyboardButton(text="🛡 Limit IP", callback_data="set_cfg:default_ip_limit")],
        [InlineKeyboardButton(text="📦 Kuota (GB)", callback_data="set_cfg:default_quota_gb"), InlineKeyboardButton(text="🚀 Speed (Mbps)", callback_data="set_cfg:default_speed_mbps")],
        [InlineKeyboardButton(text="👥 Max User VPS", callback_data="set_cfg:max_users_per_vps"), InlineKeyboardButton(text="🔄 Reset Limit Semua User", callback_data="adm_reset_all_quotas")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "adm_group_cfg")
async def cb_adm_group_cfg(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()
    notif_c = "ON 🟢" if get_setting("notif_create_group", "1") == "1" else "OFF 🔴"
    grp_id = get_setting("group_chat_id", "") or "Belum Diatur"
    fj_chat = get_setting("force_join_chat", "") or "Tidak Aktif"
    fj_link = get_setting("force_join_link", "") or "-"

    with db_conn() as conn:
        topics = conn.execute("SELECT * FROM detected_topics ORDER BY updated_at DESC LIMIT 6").fetchall()

    txt = (
        "<b>WAJIB JOIN &amp; SET TOPIC GRUP</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Target Wajib Join</b> : <code>{html.escape(fj_chat)}</code>\n"
        f"• <b>URL Invite Link</b>   : <code>{html.escape(fj_link)}</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>ID Grup Notif</b>     : <code>{html.escape(grp_id)}</code>\n"
        f"• <b>Topic Multi-Login</b> : <code>Thread #{html.escape(get_setting('group_topic_id', '0'))}</code>\n"
        f"• <b>Topic Buat Akun</b>   : <code>Thread #{html.escape(get_setting('create_topic_id', '0'))}</code> ({notif_c})\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "💡 <i>Klik <b>📢 Set Wajib Join</b> untuk mengatur username/ID grup &amp; link invite, atau ketik <code>/setbuat</code> dan <code>/setlock</code> di topik grup:</i>"
    )
    kb = [
        [
            InlineKeyboardButton(text="📢 Set Wajib Join (Username/ID + Link)", callback_data="wj_wizard_start")
        ],
        [
            InlineKeyboardButton(text="🗑 Matikan Wajib Join", callback_data="wj_disable"),
            InlineKeyboardButton(text=f"Log Buat Akun ({notif_c})", callback_data="toggle_grp_create")
        ],
        [
            InlineKeyboardButton(text="📌 Set Topic Buat Akun", callback_data="easy_topic:create"),
            InlineKeyboardButton(text="🚨 Set Topic Multi-Login", callback_data="easy_topic:lock")
        ],
        [
            InlineKeyboardButton(text="🧪 Tes Topic Buat Akun", callback_data="test_topic:create"),
            InlineKeyboardButton(text="🧪 Tes Topic Multi-Login", callback_data="test_topic:lock")
        ]
    ]
    for tp in topics:
        t_lbl = f"Topik #{tp['thread_id']}" if tp["thread_id"] > 0 else "General"
        kb.append([
            InlineKeyboardButton(text=f"📌 [{tp['chat_title'][:10]}] {t_lbl} -> Buat", callback_data=f"bind_grp:{tp['chat_id']}:{tp['thread_id']}:create"),
            InlineKeyboardButton(text="🚨 -> Lock", callback_data=f"bind_grp:{tp['chat_id']}:{tp['thread_id']}:lock")
        ])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, txt, parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data == "wj_disable")
async def cb_wj_disable(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    set_setting("force_join_chat", "")
    set_setting("force_join_link", "")
    await cb.answer("✅ Fitur Wajib Join telah dimatikan!", show_alert=True)
    await cb_adm_group_cfg(cb, state)

@router.callback_query(F.data == "wj_wizard_start")
async def cb_wj_wizard_start(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    await state.set_state(FormState.admin_wj_step1_target)
    cur_fj = get_setting("force_join_chat", "") or "Belum diatur"
    await safe_edit_Basic(
        cb,
        "📢 <b>SET WAJIB JOIN — LANGKAH 1 / 2</b>\n"
        "────────────────────────────\n"
        f"• Saat ini: <code>{html.escape(cur_fj)}</code>\n\n"
        "1️⃣ Silakan ketik <b>Username Channel / Grup</b> (contoh: <code>@namachannel</code>) "
        "ATAU <b>ID Grup / Channel</b> (contoh: <code>-1001234567890</code>):\n\n"
        "<i>(Pastikan Bot sudah dimasukkan sebagai Admin di Channel/Grup tersebut. Ketik <code>off</code> untuk mematikan Wajib Join)</i>",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_group_cfg")]])
    )

@router.message(FormState.admin_wj_step1_target)
async def msg_wj_step1_target(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    target = (msg.text or "").strip()
    if not target or target.lower() in ("off", "-", "0", "disable"):
        set_setting("force_join_chat", "")
        set_setting("force_join_link", "")
        await state.clear()
        await msg.answer("✅ Wajib Join telah dimatikan.", reply_markup=admin_menu_kb())
        return

    # Jika user mengirim link t.me/namachannel di langkah 1, ubah otomatis menjadi @namachannel
    if "t.me/" in target and "/+" not in target and "joinchat/" not in target:
        slug = target.split("t.me/", 1)[1].split("/")[0].split("?")[0].strip()
        if slug:
            target = f"@{slug}"
    elif not target.startswith("@") and not target.startswith("-100") and not target.lstrip("-").isdigit():
        target = f"@{target}"

    await state.update_data(wj_target=target)
    await state.set_state(FormState.admin_wj_step2_link)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ Auto (Buat Link Otomatis)", callback_data="wj_step2_auto")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_group_cfg")]
    ])
    await msg.answer(
        f"✅ Target Channel/Grup: <code>{html.escape(target)}</code>\n\n"
        "🔗 <b>SET WAJIB JOIN — LANGKAH 2 / 2</b>\n"
        "────────────────────────────\n"
        "2️⃣ Sekarang kirimkan <b>URL Invite Link</b> channel/grup tersebut "
        "(contoh: <code>https://t.me/namachannel</code> atau <code>https://t.me/+AbCdEfGhIjK</code>),\n"
        "ATAU ketik <b><code>auto</code></b> (bisa juga klik tombol <b>⚡ Auto</b> di bawah):",
        parse_mode="HTML",
        reply_markup=kb
    )

async def finalize_wj_setup(target: str, link_input: str) -> tuple:
    link_val = link_input.strip()
    if link_val.lower() == "auto" or not link_val:
        if target.startswith("@"):
            link_val = f"https://t.me/{target.lstrip('@')}"
        else:
            try:
                chat_obj = await bot.get_chat(chat_id=target)
                if getattr(chat_obj, "username", None):
                    link_val = f"https://t.me/{chat_obj.username}"
                elif getattr(chat_obj, "invite_link", None):
                    link_val = chat_obj.invite_link
                else:
                    link_val = await bot.export_chat_invite_link(chat_id=target)
            except Exception:
                link_val = "https://t.me/"
    elif not link_val.startswith("http"):
        link_val = f"https://t.me/{link_val.lstrip('@')}"

    set_setting("force_join_chat", target)
    set_setting("force_join_link", link_val)
    return target, link_val

@router.callback_query(F.data == "wj_step2_auto")
async def cb_wj_step2_auto(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    target = data.get("wj_target", "")
    await state.clear()
    t_saved, l_saved = await finalize_wj_setup(target, "auto")
    await cb.answer("✅ Wajib Join berhasil diaktifkan!", show_alert=True)
    await safe_edit_Basic(
        cb,
        "✅ <b>WAJIB JOIN BERHASIL DISIMPAN!</b>\n"
        "────────────────────────────\n"
        f"• <b>Target Channel/Grup:</b> <code>{html.escape(t_saved)}</code>\n"
        f"• <b>URL Invite Link:</b> <code>{html.escape(l_saved)}</code>",
        reply_markup=admin_menu_kb()
    )

@router.message(FormState.admin_wj_step2_link)
async def msg_wj_step2_link(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    target = data.get("wj_target", "")
    raw_link = (msg.text or "").strip()
    await state.clear()
    t_saved, l_saved = await finalize_wj_setup(target, raw_link)
    await msg.answer(
        "✅ <b>WAJIB JOIN BERHASIL DISIMPAN!</b>\n"
        "────────────────────────────\n"
        f"• <b>Target Channel/Grup:</b> <code>{html.escape(t_saved)}</code>\n"
        f"• <b>URL Invite Link:</b> <code>{html.escape(l_saved)}</code>",
        parse_mode="HTML",
        reply_markup=admin_menu_kb()
    )

@router.callback_query(F.data.startswith("easy_topic:"))
async def cb_easy_topic(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID: return
    mode = cb.data.split(":")[1]
    await state.update_data(topic_mode=mode)
    await state.set_state(FormState.admin_manual_topic)
    await safe_edit_Basic(cb, 
        f"<b>SET TOPIC ({mode.upper()})</b>\nKirimkan <b>Link Pesan Topik</b> (<code>https://t.me/c/xxx/12/34</code>) ATAU format <code>-100xxx|TOPIC_ID</code> ATAU angka <b>Topic ID</b> saja:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_group_cfg")]])
    )

@router.message(FormState.admin_manual_topic)
async def msg_admin_manual_topic(msg: Message, state: FSMContext):
    mode = (await state.get_data()).get("topic_mode", "create")
    raw = msg.text.strip()
    await state.clear()
    chat_id = get_setting("group_chat_id", "").strip()
    topic_id = "0"
    m_link = re.search(r"t\.me/c/(\d+)/(\d+)", raw)
    if m_link:
        chat_id, topic_id = f"-100{m_link.group(1)}", m_link.group(2)
    elif "|" in raw:
        parts = [x.strip() for x in raw.split("|")]
        chat_id, topic_id = parts[0], (parts[1] if len(parts) > 1 else "0")
    else:
        m_num = re.search(r"\d+", raw)
        if m_num: topic_id = m_num.group(0)
    if chat_id: set_setting("group_chat_id", chat_id)
    if mode == "create":
        set_setting("create_topic_id", topic_id)
        set_setting("notif_create_group", "1")
    else:
        set_setting("group_topic_id", topic_id)
    await msg.answer(f"✅ Disimpan! Group: <code>{html.escape(chat_id)}</code> | Topic: <code>{html.escape(topic_id)}</code>", parse_mode="HTML", reply_markup=admin_menu_kb())



async def cb_test_topic(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    mode = cb.data.split(":")[1]
    grp_id = get_setting("group_chat_id", "").strip()
    if not grp_id:
        await cb.answer("⚠️ Group ID belum diatur! Ketik /setbuat atau /setlock di grup Anda.", show_alert=True)
        return
    tid = get_int_setting("create_topic_id" if mode == "create" else "group_topic_id", 0, 0)
    kwargs = {"chat_id": int(grp_id), "text": f"✅ <b>TES NOTIFIKASI TOPIC ({mode.upper()}) BERHASIL!</b>\n• Topic ID: <code>{tid}</code>", "parse_mode": "HTML"}
    if tid > 0: kwargs["message_thread_id"] = tid
    try:
        await bot.send_message(**kwargs)
        await cb.answer("✅ Pesan tes terkirim ke topik grup!", show_alert=True)
    except Exception as e:
        await cb.answer(f"❌ Gagal: {e}", show_alert=True)

@router.callback_query(F.data == "toggle_grp_create")
async def cb_toggle_grp_create(cb: CallbackQuery):
    set_setting("notif_create_group", "0" if get_setting("notif_create_group", "1") == "1" else "1")
    await cb_adm_group_cfg(cb)

@router.callback_query(F.data == "adm_banner_cfg")
async def cb_adm_banner_cfg(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID: return
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="Edit Banner HTML (/etc/issue.net)", callback_data="edit_banner_html")],
        [InlineKeyboardButton(text=f"Ubah Preset Bug ({get_setting('bug_host')})", callback_data="set_cfg:bug_host")],
        [InlineKeyboardButton(text="⬅️ Kembali", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, "<b>KELOLA BANNER SSH & PRESET BUG</b>", parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "edit_banner_html")
async def cb_edit_banner(cb: CallbackQuery, state: FSMContext):
    await state.set_state(FormState.admin_edit_banner)
    await safe_edit_Basic(cb, "Kirimkan kode HTML baru untuk Banner SSH (<code>/etc/issue.net</code>):", parse_mode="HTML")

@router.message(FormState.admin_edit_banner)
async def msg_save_banner(msg: Message, state: FSMContext):
    with open("/etc/issue.net", "w") as f: f.write(msg.text)
    await asyncio.to_thread(engine.run_cmd, "systemctl restart dropbear && systemctl restart ssh")
    await state.clear()
    await msg.answer("✅ Banner HTML diperbarui.", reply_markup=admin_menu_kb())

@router.callback_query(F.data.startswith("toggle_cfg:"))
async def cb_toggle_cfg(cb: CallbackQuery):
    key = cb.data.split(":")[1]
    set_setting(key, "0" if get_setting(key, "1") == "1" else "1")
    await cb_adm_lock_cfg(cb)

@router.callback_query(F.data.startswith("set_cfg:"))
async def cb_set_cfg(cb: CallbackQuery, state: FSMContext):
    key = cb.data.split(":")[1]
    await state.update_data(cfg_key=key)
    await state.set_state(FormState.admin_set_value)
    await safe_edit_Basic(cb, f"Masukkan nilai baru untuk <code>{html.escape(key)}</code> (ketik <code>-</code> untuk kosongkan):", parse_mode="HTML")

@router.message(FormState.admin_set_value)
async def msg_admin_set_val(msg: Message, state: FSMContext):
    key = (await state.get_data())["cfg_key"]
    raw_val = msg.text.strip()
    val = "" if raw_val == "-" else raw_val
    numeric_keys = {
        "lock_duration_min": (5, 1), "lock_strikes": (1, 1), "default_days": (7, 1),
        "trial_minutes": (30, 1), "default_ip_limit": (2, 1), "default_quota_gb": (50, 0),
        "default_speed_mbps": (0, 0), "max_users_per_vps": (100, 1),
        "user_create_max": (1, 0), "user_create_days": (3, 1), "trial_create_max": (3, 0),
    }
    if key in numeric_keys:
        def_v, min_v = numeric_keys[key]
        m = re.search(r"-?\d+", val)
        val = str(max(min_v, int(m.group(0)) if m else def_v))
    set_setting(key, val)
    if key == "default_speed_mbps":
        try:
            mbps = int(val)
            iface = engine.get_default_iface()
            if mbps > 0 and iface: engine.run_cmd(f"wondershaper -a {iface} -d {mbps*1024} -u {mbps*1024}")
            elif iface: engine.run_cmd(f"wondershaper -c -a {iface}")
        except Exception:
            pass
    await state.clear()
    await msg.answer(f"✅ <code>{html.escape(key)}</code> disimpan menjadi <code>{html.escape(val)}</code>.", parse_mode="HTML", reply_markup=admin_menu_kb())

@router.callback_query(F.data == "adm_relays")
async def cb_adm_relays(cb: CallbackQuery):
    with db_conn() as conn: relays = conn.execute("SELECT * FROM relays").fetchall()
    lines = ["<b>RELAY MULTI-NEGARA 1-KLIK</b>\n────────────────────────────"]
    kb = []
    for r in relays:
        lines.append(f"• <b>{html.escape(r['country'])}</b> (<code>{html.escape(r['address'])}:{r['port']}</code>) — {'🟢 AKTIF' if r['is_active']==1 else 'Standby'}")
        kb.append([InlineKeyboardButton(text=f"Aktifkan Relay {r['country']}", callback_data=f"act_relay:{r['id']}")])
    kb.extend([
        [InlineKeyboardButton(text="Matikan Relay (Direct)", callback_data="act_relay:0")],
        [InlineKeyboardButton(text="➕ Tambah Node Relay", callback_data="add_relay_node")],
        [InlineKeyboardButton(text="⬅️ Kembali", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, "\n".join(lines), parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("act_relay:"))
async def cb_act_relay(cb: CallbackQuery):
    rid = int(cb.data.split(":")[1])
    with db_conn() as conn:
        if rid == 0:
            ok, err = engine.apply_relay_outbound(None)
            if ok: conn.execute("UPDATE relays SET is_active=0"); conn.commit()
            await cb.answer("Outbound dikembalikan ke Direct VPS." if ok else f"Gagal: {err}", show_alert=True)
        else:
            row = conn.execute("SELECT * FROM relays WHERE id=?", (rid,)).fetchone()
            if row:
                ok, err = engine.apply_relay_outbound(dict(row))
                if ok:
                    conn.execute("UPDATE relays SET is_active=0")
                    conn.execute("UPDATE relays SET is_active=1 WHERE id=?", (rid,))
                    conn.commit()
                await cb.answer(f"Relay {row['country']} aktif!" if ok else f"Rollback! Error: {err}", show_alert=True)
    await cb_adm_relays(cb)

@router.callback_query(F.data == "add_relay_node")
async def cb_add_relay_node(cb: CallbackQuery, state: FSMContext):
    await state.set_state(FormState.admin_add_relay)
    await safe_edit_Basic(cb, "Kirim format:\n<code>NEGARA|IP_HOST|PORT|UUID|PROTOKOL(vless/vmess/socks)</code>", parse_mode="HTML")

@router.message(FormState.admin_add_relay)
async def msg_add_relay_node(msg: Message, state: FSMContext):
    parts = [x.strip() for x in msg.text.split("|")]
    if len(parts) < 5:
        await msg.answer("Format salah.", parse_mode="HTML"); return
    with db_conn() as conn:
        conn.execute("INSERT INTO relays (country, address, port, uuid, protocol) VALUES (?, ?, ?, ?, ?)", (parts[0], parts[1], int(parts[2]), parts[3], parts[4].lower()))
        conn.commit()
    await state.clear()
    await msg.answer(f"✅ Relay <b>{html.escape(parts[0])}</b> ditambahkan.", parse_mode="HTML", reply_markup=admin_menu_kb())

def build_component_check_screen(srv_row, temp_pass: str = None):
    sid = srv_row["id"]
    name = srv_row["name"]
    host = srv_row["host"]
    port = srv_row["ssh_port"] or 22
    res = engine.check_remote_vps_components(srv_row, temp_pass=temp_pass)
    ip_str = res.get("ip", host)

    err_banner = ""
    if not res.get("ok"):
        err_banner = (
            f"⚠️ <b>Koneksi SSH ke IPv4 Gagal:</b> <code>{html.escape(res.get('error', 'Timeout'))}</code>\n"
            f"<i>Silakan klik <b>✏️ Edit Login #{sid}</b> untuk menautkan ulang SSH Key dengan Password Root.</i>\n\n"
        )

    txt = (
        f"🔍 <b>Hasil Cek Komponen Server #{sid} — {html.escape(name)}</b>\n"
        f"• <b>Domain / IP:</b> <code>{html.escape(host)}</code> (<code>{html.escape(ip_str)}:{port}</code>)\n"
        "• <b>Keamanan Login:</b> 🔒 <code>SSH Key Terenkripsi (Password Tidak Disimpan)</code>\n\n"
        f"{err_banner}"
        "📦 <b>Status Layanan di VPS Tambahan Ini:</b>\n"
        f"• <b>Xray-Core:</b> {res['xray']}\n"
        f"• <b>Dropbear SSH:</b> {res['dropbear']}\n"
        f"• <b>HAProxy Multiplexer:</b> {res['haproxy']}\n"
        f"• <b>Nginx Web/gRPC:</b> {res['nginx']}\n"
        f"• <b>Sertifikat SSL:</b> {res['ssl']}\n\n"
        f"👇 <b>Silakan Pilih Tindakan untuk Server #{sid}:</b>\n"
        "1️⃣ Jika komponen sudah terinstal, pilih <b>Gunakan yg Sudah Ada (Tanpa Install)</b>.\n"
        "2️⃣ Jika komponen belum ada / ingin diinstal dari awal, pilih <b>Install Komponen Sekarang</b>."
    )
    kb_rows = [
        [InlineKeyboardButton(text="✅ Gunakan yg Sudah Ada (Tanpa Install)", callback_data=f"vps_use_existing:{sid}")],
        [InlineKeyboardButton(text="🛠️ Install Xray, Dropbear, HAProxy & SSL", callback_data=f"vps_full_install:{sid}")],
        [
            InlineKeyboardButton(text=f"🔄 Cek Ulang #{sid}", callback_data=f"vps_check:{sid}"),
            InlineKeyboardButton(text=f"✏️ Edit Login #{sid}", callback_data=f"vps_edit_login:{sid}")
        ],
        [
            InlineKeyboardButton(text=f"⚙️ Limit Speed/BW/User #{sid}", callback_data=f"vps_detail:{sid}"),
            InlineKeyboardButton(text=f"🗑 Hapus #{sid}", callback_data=f"vps_del:{sid}")
        ],
        [InlineKeyboardButton(text="⬅️ Kembali ke Daftar Server", callback_data="adm_vps")]
    ]
    return txt, InlineKeyboardMarkup(inline_keyboard=kb_rows)

@router.callback_query(F.data == "adm_vps")
async def cb_adm_vps(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()
    now = int(time.time())
    with db_conn() as conn:
        srvs = conn.execute("SELECT * FROM servers").fetchall()
    lines = [
        "🖥 <b>KELOLA CLUSTER MULTI-VPS</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "🔒 <i>Keamanan Aktif: Password Root tidak pernah disimpan di database bot (menggunakan SSH Key ke IPv4).</i>\n\n"
        "Pilih server di bawah untuk <b>Cek Komponen, Install Xray/Dropbear/SSL, Edit Login, atau Atur Limit</b>:"
    ]
    kb = []
    for s in srvs:
        with db_conn() as conn:
            cnt = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (s["id"], now)).fetchone()["c"]
        tp = "🟢 Lokal" if s["is_local"] == 1 else "🌐 Remote"
        ip_disp = s["ipv4"] if ("ipv4" in s.keys() and s["ipv4"]) else (PUBLIC_IP if s["is_local"] == 1 else "-")
        max_u = s["max_users"] if s["max_users"] else 100
        bw_gb = s["max_bw_gb"] if "max_bw_gb" in s.keys() and s["max_bw_gb"] else 1000
        spd = s["speed_mbps"] if "speed_mbps" in s.keys() and s["speed_mbps"] else 0
        spd_str = f"{spd} Mbps" if spd > 0 else "Unl"
        lines.append(
            f"• <b>#{s['id']} {html.escape(s['name'])}</b> [{tp}]\n"
            f"  ├ Domain: <code>{html.escape(s['host'])}</code>\n"
            f"  ╰ User: <code>{cnt}/{max_u}</code> | BW: <code>{bw_gb} GB</code> | Speed: <code>{spd_str}</code>"
        )
        if s["is_local"] == 1:
            kb.append([InlineKeyboardButton(text=f"⚙️ Kelola #{s['id']} — {s['name']} (Lokal)", callback_data=f"vps_detail:{s['id']}")])
        else:
            kb.append([
                InlineKeyboardButton(text=f"🔍 Cek & Install #{s['id']} ({s['name']})", callback_data=f"vps_check:{s['id']}"),
                InlineKeyboardButton(text=f"⚙️ Limit #{s['id']}", callback_data=f"vps_detail:{s['id']}")
            ])

    kb.append([InlineKeyboardButton(text="➕ Tambah VPS Baru (5 Langkah Aman)", callback_data="add_vps_node")])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, "\n".join(lines), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("vps_check:"))
async def cb_vps_check(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    srv_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    if not srv:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await cb.answer(f"🔍 Mengecek komponen Server #{srv_id}...")
    txt, kb = await asyncio.to_thread(build_component_check_screen, srv)
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data.startswith("vps_use_existing:"))
async def cb_vps_use_existing(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    srv_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    if not srv:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await cb.answer("⏳ Menautkan komponen yang sudah ada...")
    ok, msg_info = await asyncio.to_thread(engine.use_existing_remote_vps, srv)
    txt, kb = await asyncio.to_thread(build_component_check_screen, srv)
    status_hdr = f"✅ <b>Server #{srv_id} ({html.escape(srv['name'])}) Siap Digunakan!</b>\n<i>{html.escape(msg_info)}</i>\n\n" if ok else f"❌ <b>Gagal:</b> <code>{html.escape(msg_info)}</code>\n\n"
    await safe_edit_Basic(cb, status_hdr + txt, reply_markup=kb)

@router.callback_query(F.data.startswith("vps_full_install:"))
async def cb_vps_full_install(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    srv_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    if not srv:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await cb.answer("🛠️ Memulai instalasi penuh di VPS tambahan...")
    ip_disp = srv["ipv4"] if ("ipv4" in srv.keys() and srv["ipv4"]) else srv["host"]
    await safe_edit_Basic(
        cb,
        f"⏳ <b>MENGINSTAL KOMPONEN DI SERVER #{srv_id} — {html.escape(srv['name'])}</b>\n"
        f"• Domain: <code>{html.escape(srv['host'])}</code> (IPv4: <code>{html.escape(ip_disp)}</code>)\n\n"
        "<i>Sedang memasang Xray-Core, Dropbear v2019.78, Multiplexer, Nginx Stream, Banner HTML, dan Sertifikat SSL. Mohon tunggu ±1-2 menit...</i>"
    )
    ok, msg_info = await asyncio.to_thread(engine.install_full_remote_vps_sync, srv)
    txt, kb = await asyncio.to_thread(build_component_check_screen, srv)
    hdr = f"✅ <b>INSTALASI SELESAI!</b>\n<i>{html.escape(msg_info)}</i>\n\n" if ok else f"⚠️ <b>CATATAN INSTALASI:</b>\n<code>{html.escape(msg_info)}</code>\n\n"
    await safe_edit_Basic(cb, hdr + txt, reply_markup=kb)

# ==============================================================================
# WIZARD 5 LANGKAH: EDIT LOGIN SERVER #{ID} (NAMA, DOMAIN, IPV4, PORT, PASS ROOT)
# ==============================================================================
@router.callback_query(F.data.startswith("vps_edit_login:"))
async def cb_vps_edit_login(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    srv_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    if not srv:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await state.update_data(edit_login_sid=srv_id)
    await state.set_state(FormState.vps_edit_name)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚡ Tetap Pakai: {srv['name']}", callback_data="vps_keep_name")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]
    ])
    await safe_edit_Basic(
        cb,
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 1 / 5 (NAMA SERVER)</b>\n"
        "────────────────────────────\n"
        f"Nama Server saat ini: <b>{html.escape(srv['name'])}</b>\n\n"
        "1️⃣ Ketik <b>Nama Server Baru</b>, atau klik tombol di bawah untuk tetap memakai nama saat ini:",
        reply_markup=kb
    )

@router.callback_query(F.data == "vps_keep_name")
async def cb_vps_keep_name(cb: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    await state.update_data(new_name=srv["name"])
    await state.set_state(FormState.vps_edit_host)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚡ Tetap Pakai: {srv['host']}", callback_data="vps_keep_host")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]
    ])
    await safe_edit_Basic(
        cb,
        f"✅ Nama Server: <b>{html.escape(srv['name'])}</b>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 2 / 5 (DOMAIN / SUBDOMAIN)</b>\n"
        "────────────────────────────\n"
        "2️⃣ Ketik <b>Domain / Subdomain</b> baru, atau klik tombol di bawah:",
        reply_markup=kb
    )

@router.message(FormState.vps_edit_name)
async def msg_vps_edit_name(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    new_name = msg.text.strip() or srv["name"]
    await state.update_data(new_name=new_name)
    await state.set_state(FormState.vps_edit_host)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚡ Tetap Pakai: {srv['host']}", callback_data="vps_keep_host")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]
    ])
    await msg.answer(
        f"✅ Nama Server: <b>{html.escape(new_name)}</b>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 2 / 5 (DOMAIN / SUBDOMAIN)</b>\n"
        "────────────────────────────\n"
        "2️⃣ Ketik <b>Domain / Subdomain</b> baru, atau klik tombol di bawah:",
        parse_mode="HTML",
        reply_markup=kb
    )

@router.callback_query(F.data == "vps_keep_host")
async def cb_vps_keep_host(cb: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    await state.update_data(new_host=srv["host"])
    await state.set_state(FormState.vps_edit_ipv4)
    cur_ip = srv["ipv4"] if ("ipv4" in srv.keys() and srv["ipv4"]) else ""
    kb_rows = []
    if cur_ip:
        kb_rows.append([InlineKeyboardButton(text=f"⚡ Tetap Pakai IPv4: {cur_ip}", callback_data="vps_keep_ipv4")])
    kb_rows.append([InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")])
    await safe_edit_Basic(
        cb,
        f"✅ Domain / Subdomain: <code>{html.escape(srv['host'])}</code>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 3 / 5 (IPV4 VPS)</b>\n"
        "────────────────────────────\n"
        "3️⃣ Ketik <b>Alamat IPv4 Publik VPS</b> (contoh: <code>169.40.151.7</code>):",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows)
    )

@router.message(FormState.vps_edit_host)
async def msg_vps_edit_host(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    host = msg.text.strip().replace("http://", "").replace("https://", "").split("/")[0]
    await state.update_data(new_host=host)
    await state.set_state(FormState.vps_edit_ipv4)
    cur_ip = srv["ipv4"] if ("ipv4" in srv.keys() and srv["ipv4"]) else ""
    kb_rows = []
    if cur_ip:
        kb_rows.append([InlineKeyboardButton(text=f"⚡ Tetap Pakai IPv4: {cur_ip}", callback_data="vps_keep_ipv4")])
    kb_rows.append([InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")])
    await msg.answer(
        f"✅ Domain / Subdomain: <code>{html.escape(host)}</code>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 3 / 5 (IPV4 VPS)</b>\n"
        "────────────────────────────\n"
        "3️⃣ Ketik <b>Alamat IPv4 Publik VPS</b> (contoh: <code>169.40.151.7</code>):",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows)
    )

@router.callback_query(F.data == "vps_keep_ipv4")
async def cb_vps_keep_ipv4(cb: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    cur_ip = srv["ipv4"] if ("ipv4" in srv.keys() and srv["ipv4"]) else srv["host"]
    await state.update_data(new_ipv4=cur_ip)
    await state.set_state(FormState.vps_edit_port)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚡ Gunakan Port {srv['ssh_port'] or 22}", callback_data="vps_keep_port")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]
    ])
    await safe_edit_Basic(
        cb,
        f"✅ IPv4 VPS: <code>{html.escape(cur_ip)}</code>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 4 / 5 (PORT SSH)</b>\n"
        "────────────────────────────\n"
        "4️⃣ Masukkan <b>Port SSH</b>, atau klik tombol di bawah:",
        reply_markup=kb
    )

@router.message(FormState.vps_edit_ipv4)
async def msg_vps_edit_ipv4(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    ipv4 = msg.text.strip()
    await state.update_data(new_ipv4=ipv4)
    await state.set_state(FormState.vps_edit_port)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⚡ Gunakan Port {srv['ssh_port'] or 22}", callback_data="vps_keep_port")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]
    ])
    await msg.answer(
        f"✅ IPv4 VPS: <code>{html.escape(ipv4)}</code>\n\n"
        f"✏️ <b>EDIT SERVER #{srv_id} — LANGKAH 4 / 5 (PORT SSH)</b>\n"
        "────────────────────────────\n"
        "4️⃣ Masukkan <b>Port SSH</b> (angka), atau klik tombol di bawah:",
        parse_mode="HTML",
        reply_markup=kb
    )

@router.callback_query(F.data == "vps_keep_port")
async def cb_vps_keep_port(cb: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
    await state.update_data(new_port=srv["ssh_port"] or 22)
    await state.set_state(FormState.vps_edit_pass)
    await safe_edit_Basic(
        cb,
        f"✅ Port SSH: <code>{srv['ssh_port'] or 22}</code>\n\n"
        f"🔑 <b>EDIT SERVER #{srv_id} — LANGKAH 5 / 5 (PASSWORD ROOT)</b>\n"
        "────────────────────────────\n"
        "5️⃣ Ketik <b>Password Root SSH</b> VPS ini:\n"
        "🔒 <i>(Pesan password Anda akan langsung dihapus otomatis dari chat &amp; TIDAK disimpan di database bot)</i>",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]])
    )

@router.message(FormState.vps_edit_port)
async def msg_vps_edit_port(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    m = re.search(r"\d+", msg.text.strip())
    port = int(m.group(0)) if m else 22
    await state.update_data(new_port=port)
    await state.set_state(FormState.vps_edit_pass)
    await msg.answer(
        f"✅ Port SSH: <code>{port}</code>\n\n"
        f"🔑 <b>EDIT SERVER #{srv_id} — LANGKAH 5 / 5 (PASSWORD ROOT)</b>\n"
        "────────────────────────────\n"
        "5️⃣ Ketik <b>Password Root SSH</b> VPS ini:\n"
        "🔒 <i>(Pesan password Anda akan langsung dihapus otomatis dari chat &amp; TIDAK disimpan di database bot)</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_check:{srv_id}")]])
    )

@router.message(FormState.vps_edit_pass)
async def msg_vps_edit_pass(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_login_sid"]
    new_name = data.get("new_name", "VPS")
    new_host = data["new_host"]
    new_ipv4 = data["new_ipv4"]
    new_port = int(data["new_port"])
    temp_pass = msg.text.strip()
    await state.clear()

    # Hapus pesan password dari chat Telegram agar aman
    try:
        await msg.delete()
    except Exception:
        pass

    wait_msg = await msg.answer(
        f"🔒 <b>Pesan password telah dihapus demi keamanan!</b>\n"
        f"⏳ <i>Menautkan SSH Key ke <code>{html.escape(new_ipv4)}:{new_port}</code> &amp; mengecek komponen Server #{srv_id}...</i>",
        parse_mode="HTML"
    )
    _, city, isp = await asyncio.to_thread(engine.lookup_host_geo, new_ipv4)
    with db_conn() as conn:
        conn.execute(
            "UPDATE servers SET name=?, host=?, ipv4=?, city=?, isp=?, ssh_port=?, ssh_pass='' WHERE id=?",
            (new_name, new_host, new_ipv4, city, isp, new_port, srv_id)
        )
        conn.commit()
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()

    txt, kb = await asyncio.to_thread(build_component_check_screen, srv, temp_pass)
    del temp_pass
    await wait_msg.edit_text(txt, parse_mode="HTML", reply_markup=kb)

def render_vps_detail_view(srv_id: int):
    now = int(time.time())
    with db_conn() as conn:
        s = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
        if not s:
            return None, None
        cnt = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (srv_id, now)).fetchone()["c"]
    tp = "🟢 Server Utama (Lokal)" if s["is_local"] == 1 else f"🌐 Remote VPS (SSH Port {s['ssh_port']})"
    ip_disp = s["ipv4"] if ("ipv4" in s.keys() and s["ipv4"]) else (PUBLIC_IP if s["is_local"] == 1 else "-")
    max_u = s["max_users"] if s["max_users"] else 100
    bw_gb = s["max_bw_gb"] if "max_bw_gb" in s.keys() and s["max_bw_gb"] else 1000
    spd = s["speed_mbps"] if "speed_mbps" in s.keys() and s["speed_mbps"] else 0
    spd_lbl = f"{spd} Mbps" if spd > 0 else "Unlimited (0)"

    txt = (
        f"🖥 <b>PENGATURAN LIMIT SERVER #{s['id']} — {html.escape(s['name'])}</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Tipe Server</b>    : {tp}\n"
        f"• <b>Domain / Host</b>  : <code>{html.escape(s['host'])}</code>\n"
        f"• <b>IPv4 Server</b>    : <code>{html.escape(ip_disp)}</code>\n"
        f"• <b>Lokasi / ISP</b>   : {html.escape(s['city'])} — {html.escape(s['isp'])}\n"
        f"• <b>Kapasitas User</b> : <b>{cnt} / {max_u} Akun</b>\n"
        f"• <b>Max Bandwidth</b>  : <b>{bw_gb} GB</b>\n"
        f"• <b>Limit Speed</b>    : <b>{spd_lbl}</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Pilih pengaturan untuk server ini:"
    )
    kb_rows = [
        [
            InlineKeyboardButton(text="🚀 Atur Speed (Mbps)", callback_data=f"vps_set:{srv_id}:speed"),
            InlineKeyboardButton(text="📦 Atur Max Bandwidth", callback_data=f"vps_set:{srv_id}:bw")
        ],
        [
            InlineKeyboardButton(text="👥 Atur Max User", callback_data=f"vps_set:{srv_id}:maxu"),
            InlineKeyboardButton(text=f"🔍 Cek Komponen #{srv_id}", callback_data=f"vps_check:{srv_id}")
        ]
    ]
    if s["is_local"] == 0:
        kb_rows.append([
            InlineKeyboardButton(text=f"✏️ Edit Login #{srv_id}", callback_data=f"vps_edit_login:{srv_id}"),
            InlineKeyboardButton(text=f"🗑 Hapus VPS #{srv_id}", callback_data=f"vps_del:{srv_id}")
        ])
    kb_rows.append([InlineKeyboardButton(text="⬅️ Kembali ke Daftar Server", callback_data="adm_vps")])
    return txt, InlineKeyboardMarkup(inline_keyboard=kb_rows)

@router.callback_query(F.data.startswith("vps_detail:"))
async def cb_vps_detail(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    srv_id = int(cb.data.split(":")[1])
    txt, kb = render_vps_detail_view(srv_id)
    if not txt:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data.startswith("vps_set:"))
async def cb_vps_set_param(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    _, srv_id_str, field = cb.data.split(":")
    srv_id = int(srv_id_str)
    await state.update_data(edit_srv_id=srv_id, edit_srv_field=field)
    await state.set_state(FormState.admin_vps_edit_val)
    labels = {
        "speed": "🚀 Masukkan batas <b>Speed Limit VPS dalam Mbps</b> (ketik <code>0</code> untuk Unlimited):",
        "bw": "📦 Masukkan batas <b>Max Bandwidth VPS dalam GB</b> (contoh: <code>1000</code>):",
        "maxu": "👥 Masukkan batas <b>Maksimal User Aktif</b> untuk VPS ini (contoh: <code>100</code>):"
    }
    await safe_edit_Basic(
        cb,
        labels.get(field, "Masukkan nilai baru:"),
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data=f"vps_detail:{srv_id}")]])
    )

@router.message(FormState.admin_vps_edit_val)
async def msg_admin_vps_edit_val(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    data = await state.get_data()
    srv_id = data["edit_srv_id"]
    field = data["edit_srv_field"]
    m = re.search(r"\d+", msg.text.strip())
    val = int(m.group(0)) if m else 0
    await state.clear()

    with db_conn() as conn:
        if field == "speed":
            conn.execute("UPDATE servers SET speed_mbps=? WHERE id=?", (val, srv_id))
            conn.commit()
            srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
            await asyncio.to_thread(engine.apply_server_speed, srv, val)
        elif field == "bw":
            val = max(1, val)
            conn.execute("UPDATE servers SET max_bw_gb=? WHERE id=?", (val, srv_id))
            conn.commit()
            if srv_id == 1:
                set_setting("default_quota_gb", str(val))
        elif field == "maxu":
            val = max(1, val)
            conn.execute("UPDATE servers SET max_users=? WHERE id=?", (val, srv_id))
            conn.commit()
            if srv_id == 1:
                set_setting("max_users_per_vps", str(val))

    txt, kb = render_vps_detail_view(srv_id)
    await msg.answer(f"✅ Pengaturan VPS berhasil diperbarui!\n\n{txt}", parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("vps_del:"))
async def cb_vps_del(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    srv_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (srv_id,)).fetchone()
        if not srv or srv["is_local"] == 1:
            await cb.answer("⚠️ Server Utama (Lokal) tidak dapat dihapus!", show_alert=True)
            return
        conn.execute("DELETE FROM servers WHERE id=?", (srv_id,))
        conn.execute("DELETE FROM accounts WHERE server_id=?", (srv_id,))
        conn.commit()
    resequence_servers_db()
    await cb.answer(f"🗑 VPS {srv['name']} berhasil dihapus permanen dari database & nomor urut dirapikan!", show_alert=True)
    await cb_adm_vps(cb, state)

# ==============================================================================
# WIZARD 5 LANGKAH: TAMBAH VPS BARU (NAMA, DOMAIN, IPV4, PORT, PASS ROOT)
# ==============================================================================
@router.callback_query(F.data == "add_vps_node")
async def cb_add_vps_node(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    await state.set_state(FormState.vps_add_name)
    await safe_edit_Basic(
        cb,
        "🖥 <b>TAMBAH VPS BARU — LANGKAH 1 / 5 (NAMA SERVER)</b>\n"
        "────────────────────────────\n"
        "1️⃣ Silakan ketik <b>Nama Server VPS</b> yang ingin ditambahkan\n"
        "<i>(Contoh: <code>Atlantic</code> atau <code>ID Home</code>)</i>:",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]])
    )

@router.message(FormState.vps_add_name)
async def msg_vps_step_name(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    name = msg.text.strip()
    if not name:
        await msg.answer("⚠️ Nama server tidak boleh kosong. Silakan ketik Nama Server:")
        return
    await state.update_data(vps_name=name)
    await state.set_state(FormState.vps_add_host)
    await msg.answer(
        f"✅ Nama Server: <b>{html.escape(name)}</b>\n\n"
        "🌐 <b>TAMBAH VPS BARU — LANGKAH 2 / 5 (DOMAIN / SUBDOMAIN)</b>\n"
        "────────────────────────────\n"
        "2️⃣ Sekarang ketik <b>Domain atau Subdomain VPS</b> tersebut\n"
        "<i>(Contoh: <code>idhome.suneku.web.id</code>)</i>:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]])
    )

@router.message(FormState.vps_add_host)
async def msg_vps_step_host(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    host = msg.text.strip().replace("http://", "").replace("https://", "").split("/")[0]
    if not host:
        await msg.answer("⚠️ Domain/Subdomain tidak valid. Silakan ketik ulang:")
        return
    await state.update_data(vps_host=host)
    await state.set_state(FormState.vps_add_ipv4)
    await msg.answer(
        f"✅ Domain / Subdomain: <code>{html.escape(host)}</code>\n\n"
        "📡 <b>TAMBAH VPS BARU — LANGKAH 3 / 5 (IPV4 VPS)</b>\n"
        "────────────────────────────\n"
        "3️⃣ Sekarang ketik <b>Alamat IPv4 Publik VPS</b> tersebut\n"
        "<i>(Contoh: <code>169.40.151.7</code>)</i>:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]])
    )

@router.message(FormState.vps_add_ipv4)
async def msg_vps_step_ipv4(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    ipv4 = msg.text.strip()
    if not ipv4:
        await msg.answer("⚠️ IPv4 tidak boleh kosong. Silakan ketik ulang:")
        return
    await state.update_data(vps_ipv4=ipv4)
    await state.set_state(FormState.vps_add_port)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ Gunakan Port 22 (Default)", callback_data="vps_use_port22")],
        [InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]
    ])
    await msg.answer(
        f"✅ IPv4 VPS: <code>{html.escape(ipv4)}</code>\n\n"
        "🔌 <b>TAMBAH VPS BARU — LANGKAH 4 / 5 (PORT SSH)</b>\n"
        "────────────────────────────\n"
        "4️⃣ Masukkan <b>Port SSH VPS</b> (angka), atau klik tombol <b>⚡ Gunakan Port 22 (Default)</b> di bawah:",
        parse_mode="HTML",
        reply_markup=kb
    )

@router.callback_query(F.data == "vps_use_port22")
async def cb_vps_use_port22(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.update_data(vps_port=22)
    await state.set_state(FormState.vps_add_pass)
    await safe_edit_Basic(
        cb,
        "✅ Port SSH: <code>22</code>\n\n"
        "🔑 <b>TAMBAH VPS BARU — LANGKAH 5 / 5 (PASSWORD ROOT)</b>\n"
        "────────────────────────────\n"
        "5️⃣ Sekarang ketik <b>Password Root SSH</b> dari VPS tersebut:\n"
        "🔒 <i>(Demi keamanan, pesan password Anda akan langsung dihapus otomatis dari chat dan TIDAK disimpan di database bot)</i>",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]])
    )

@router.message(FormState.vps_add_port)
async def msg_vps_step_port(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    m = re.search(r"\d+", msg.text.strip())
    port = int(m.group(0)) if m else 22
    await state.update_data(vps_port=port)
    await state.set_state(FormState.vps_add_pass)
    await msg.answer(
        f"✅ Port SSH: <code>{port}</code>\n\n"
        "🔑 <b>TAMBAH VPS BARU — LANGKAH 5 / 5 (PASSWORD ROOT)</b>\n"
        "────────────────────────────\n"
        "5️⃣ Sekarang ketik <b>Password Root SSH</b> dari VPS tersebut:\n"
        "🔒 <i>(Demi keamanan, pesan password Anda akan langsung dihapus otomatis dari chat dan TIDAK disimpan di database bot)</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_vps")]])
    )

@router.message(FormState.vps_add_pass)
async def msg_vps_step_pass(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    temp_pass = msg.text.strip()
    data = await state.get_data()
    name = data.get("vps_name", "VPS Remote")
    host = data.get("vps_host", "")
    ipv4 = data.get("vps_ipv4", host)
    port = int(data.get("vps_port", 22))
    await state.clear()

    # Hapus pesan password dari chat Telegram seketika
    try:
        await msg.delete()
    except Exception:
        pass

    wait_msg = await msg.answer(
        f"🔒 <b>Pesan password telah dihapus otomatis demi keamanan!</b>\n"
        f"🔍 <i>Menautkan SSH Key ke <code>{html.escape(ipv4)}:{port}</code> &amp; mengecek komponen Server {html.escape(name)}...</i>",
        parse_mode="HTML"
    )
    _, city, isp = await asyncio.to_thread(engine.lookup_host_geo, ipv4)

    # Rapikan urutan ID terlebih dahulu lalu simpan di nomor urut berikutnya (TANPA password)
    resequence_servers_db()
    with db_conn() as conn:
        next_id = (conn.execute("SELECT COALESCE(MAX(id), 0) FROM servers").fetchone()[0]) + 1
        conn.execute(
            "INSERT INTO servers (id, name, host, ipv4, city, isp, ssh_port, ssh_pass, max_users, max_bw_gb, speed_mbps, is_local) VALUES (?, ?, ?, ?, ?, ?, ?, '', 100, 1000, 0, 0)",
            (next_id, name, host, ipv4, city, isp, port)
        )
        conn.commit()
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (next_id,)).fetchone()

    txt, kb = await asyncio.to_thread(build_component_check_screen, srv, temp_pass)
    del temp_pass
    await wait_msg.edit_text(txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "server_info")
async def cb_server_info(cb: CallbackQuery):
    await cb.answer("⏳ Memuat Status Server...")
    txt = build_admin_dashboard_text(user_id=cb.from_user.id, include_rules=True)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔄 Refresh Status Server", callback_data="server_info")],
        [InlineKeyboardButton(text="🏠 Kembali ke Menu Utama", callback_data="back_home")]
    ])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data == "adm_logs")
async def cb_adm_logs(cb: CallbackQuery):
    with db_conn() as conn: logs = conn.execute("SELECT * FROM activity_logs ORDER BY id DESC LIMIT 15").fetchall()
    lines = ["<b>15 LOG AKTIVITAS TERAKHIR</b>\n────────────────────────────"]
    for l in logs:
        lines.append(f"• <code>[{datetime.fromtimestamp(l['ts']).strftime('%d/%m %H:%M:%S')}]</code> <b>{html.escape(l['event'])}</b>: {html.escape(l['detail'])}")
    await safe_edit_Basic(cb, "\n".join(lines), parse_mode="HTML", reply_markup=admin_menu_kb())


# ==============================================================================
# FITUR BARU 1: KELOLA WELCOME MESSAGE (TEKS & FOTO/BANNER)
# ==============================================================================
@router.callback_query(F.data == "adm_welcome_cfg")
async def cb_adm_welcome_cfg(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    has_photo = "✅ Ada Foto/Banner" if get_setting("welcome_photo", "").strip() else "❌ Tanpa Foto (Hanya Teks)"
    has_text = "Custom Teks" if get_setting("welcome_text", "").strip() else "Default Panel"
    preview = format_welcome_caption(ADMIN_ID)
    txt = (
        "<b>PENGATURAN WELCOME (TEKS & FOTO)</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Mode Teks</b> : {has_text}\n"
        f"• <b>Foto/Banner</b> : {has_photo}\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "<b>Preview Teks Welcome Saat Ini:</b>\n\n"
        f"{preview}\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "<i>Variabel otomatis yang bisa dipakai di dalam teks:</i>\n"
        "<code>{domain}</code> <code>{lokasi}</code> <code>{isp}</code> <code>{limit_ip}</code> <code>{kuota_buat}</code> <code>{server}</code> <code>{status_bot}</code>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📝 Edit Teks Welcome", callback_data="wel_act:edit_text"),
            InlineKeyboardButton(text="🖼 Pasang / Ganti Foto", callback_data="wel_act:edit_photo")
        ],
        [
            InlineKeyboardButton(text="🗑 Hapus Foto", callback_data="wel_act:del_photo"),
            InlineKeyboardButton(text="🔄 Reset Teks Default", callback_data="wel_act:reset_text")
        ],
        [InlineKeyboardButton(text="👁 Tes Tampilan Welcome", callback_data="back_home")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data.startswith("wel_act:"))
async def cb_wel_act(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    if act == "del_photo":
        set_setting("welcome_photo", "")
        await cb.answer("✅ Foto Welcome dihapus (kembali ke mode teks).", show_alert=True)
        await cb_adm_welcome_cfg(cb, state)
    elif act == "reset_text":
        set_setting("welcome_text", "")
        await cb.answer("✅ Teks Welcome dikembalikan ke format Default.", show_alert=True)
        await cb_adm_welcome_cfg(cb, state)
    elif act == "edit_text":
        await state.set_state(FormState.admin_edit_welcome_text)
        cur_txt = format_welcome_caption(ADMIN_ID)
        await safe_edit_Basic(
            cb,
            "📝 <b>EDIT TEKS WELCOME</b>\n"
            "────────────────────────────\n"
            "Kirimkan teks Welcome baru yang Anda inginkan (mendukung format HTML seperti <code>&lt;b&gt;tebal&lt;/b&gt;</code>, <code>&lt;code&gt;kode&lt;/code&gt;</code>).\n\n"
            "<b>Teks saat ini (bisa disalin & diedit):</b>\n"
            f"<pre>{html.escape(cur_txt)}</pre>\n"
            "<i>Variabel dinamis opsional:</i> <code>{domain}</code>, <code>{lokasi}</code>, <code>{isp}</code>, <code>{limit_ip}</code>, <code>{kuota_buat}</code>, <code>{server}</code>, <code>{status_bot}</code>",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_welcome_cfg")]])
        )
    elif act == "edit_photo":
        await state.set_state(FormState.admin_edit_welcome_photo)
        await safe_edit_Basic(
            cb,
            "🖼 <b>PASANG / GANTI FOTO WELCOME</b>\n"
            "────────────────────────────\n"
            "Silakan <b>kirimkan gambar/foto</b> ke ruang chat ini.\n"
            "• Jika Anda mengisi <i>Caption</i> pada foto, maka teks Welcome akan ikut diperbarui sesuai caption tersebut.\n"
            "• Jika dikirim tanpa caption, foto akan dipasangkan dengan teks Welcome yang sudah ada.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_welcome_cfg")]])
        )

@router.message(FormState.admin_edit_welcome_text)
async def msg_admin_welcome_text(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    new_text = msg.html_text if msg.html_text else (msg.text or "")
    set_setting("welcome_text", new_text)
    await state.clear()
    await msg.answer("✅ <b>Teks Welcome berhasil diperbarui!</b>", parse_mode="HTML", reply_markup=admin_menu_kb())

@router.message(FormState.admin_edit_welcome_photo)
async def msg_admin_welcome_photo(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    if not msg.photo:
        await msg.answer("⚠️ Harap kirimkan berupa <b>Foto / Gambar</b> (bukan teks/dokumen), atau klik Batal.", parse_mode="HTML")
        return
    file_id = msg.photo[-1].file_id
    set_setting("welcome_photo", file_id)
    if msg.caption:
        cap_html = msg.html_text if hasattr(msg, "html_text") and msg.html_text else msg.caption
        set_setting("welcome_text", cap_html)
    await state.clear()
    await msg.answer("✅ <b>Foto/Banner Welcome berhasil dipasang!</b> Ketik /start untuk melihat hasilnya.", parse_mode="HTML", reply_markup=admin_menu_kb())

# ==============================================================================
# FITUR BARU 2: INJECT BUG & MULTI-CLIENT DI MENU AKUN SAYA
# ==============================================================================
def build_inject_mode_menu(acc_row, srv_row):
    uname = acc_row["username"]
    proto = acc_row["protocol"].upper()
    domain = srv_row["host"]
    acc_id = acc_row["id"]
    txt = (
        f"🎯 <b>Pilih Metode Inject Bug — {html.escape(uname)} ({proto})</b>\n"
        f"🌐 <b>Server:</b> <code>{html.escape(domain)}</code>\n\n"
        "Silakan pilih metode pemasangan bug yang ingin Anda gunakan:\n"
        "1️⃣ <b>Wildcard (bug.domain):</b> <code>Address = bug, SNI &amp; Host = bug.domain</code>\n"
        "2️⃣ <b>SNI / SSL (Spoof):</b> <code>Address = domain, SNI &amp; Host = bug</code>\n"
        "3️⃣ <b>CDN / Direct WS:</b> <code>Address = bug, SNI &amp; Host = domain</code>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="1️⃣ Mode Wildcard (bug.domain)", callback_data=f"inj_pickmode:{acc_id}:wildcard")],
        [InlineKeyboardButton(text="2️⃣ Mode SNI / SSL (Spoof Bug)", callback_data=f"inj_pickmode:{acc_id}:sni")],
        [InlineKeyboardButton(text="3️⃣ Mode CDN / WS (Direct)", callback_data=f"inj_pickmode:{acc_id}:cdn")],
        [InlineKeyboardButton(text="⚡ Tampilkan Tanpa Bug (Default)", callback_data=f"inj_render:{acc_id}:default")],
        [InlineKeyboardButton(text="⬅️ Kembali ke Akun Saya", callback_data="my_accounts")]
    ])
    return txt, kb

@router.callback_query(F.data.startswith("inj_menu:"))
async def cb_inj_menu(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    acc_id = int(cb.data.split(":")[1])
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()
    txt, kb = build_inject_mode_menu(acc, srv)
    await safe_edit_Basic(cb, txt, reply_markup=kb)

def get_bug_presets_list():
    with db_conn() as conn:
        rows = conn.execute("SELECT bug_host FROM bug_presets ORDER BY id ASC").fetchall()
    return [r["bug_host"] for r in rows] if rows else ["v.whatsapp.net", "ava.game.naver.com", "quiz.vidio.com"]

@router.callback_query(F.data.startswith("inj_pickmode:"))
async def cb_inj_pickmode(cb: CallbackQuery, state: FSMContext):
    _, acc_id_str, mode = cb.data.split(":")
    acc_id = int(acc_id_str)
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return

    await state.update_data(inj_acc_id=acc_id, inj_mode=mode)
    await state.set_state(FormState.user_input_bug)

    presets = get_bug_presets_list()
    kb_rows = [
        [InlineKeyboardButton(text="✍️ Input Bug Sendiri (Ketik Manual)", callback_data=f"inj_manual_prompt:{acc_id}:{mode}")]
    ]
    row_tmp = []
    for b in presets:
        row_tmp.append(InlineKeyboardButton(text=f"🐞 {b}", callback_data=f"inj_setbug:{acc_id}:{mode}:{b}"))
        if len(row_tmp) == 2:
            kb_rows.append(row_tmp)
            row_tmp = []
    if row_tmp:
        kb_rows.append(row_tmp)
    kb_rows.append([InlineKeyboardButton(text="⬅️ Kembali Pilih Mode", callback_data=f"inj_menu:{acc_id}")])

    await safe_edit_Basic(
        cb,
        f"🎯 <b>PILIH ATAU KETIK BUG ({mode.upper()})</b>\n"
        "────────────────────────────\n"
        "• Klik salah satu tombol <b>Preset Bug</b> di bawah, ATAU\n"
        "• Langsung <b>ketik dan kirimkan Domain / IP Bug</b> Anda sendiri ke chat ini:",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows)
    )

@router.callback_query(F.data.startswith("inj_manual_prompt:"))
async def cb_inj_manual_prompt(cb: CallbackQuery, state: FSMContext):
    _, acc_id_str, mode = cb.data.split(":")
    acc_id = int(acc_id_str)
    await state.update_data(inj_acc_id=acc_id, inj_mode=mode)
    await state.set_state(FormState.user_input_bug)
    await safe_edit_Basic(
        cb,
        f"✍️ <b>INPUT BUG MANUAL ({mode.upper()})</b>\n"
        "────────────────────────────\n"
        "Silakan ketik dan kirimkan <b>Domain / Host / IP Bug</b> yang ingin Anda gunakan (contoh: <code>v.whatsapp.net</code> atau <code>104.18.2.2</code>):",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Kembali", callback_data=f"inj_pickmode:{acc_id}:{mode}")]])
    )

@router.callback_query(F.data.startswith("inj_setbug:"))
async def cb_inj_setbug(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    _, acc_id_str, mode, bug_val = cb.data.split(":", 3)
    acc_id = int(acc_id_str)
    with db_conn() as conn:
        conn.execute("UPDATE accounts SET custom_bug=?, bug_mode=? WHERE id=?", (bug_val, mode, acc_id))
        conn.commit()
    await render_injected_config_screen(cb, acc_id, mode, bug_val, is_message=False)

@router.message(FormState.user_input_bug)
async def msg_user_input_bug(msg: Message, state: FSMContext):
    data = await state.get_data()
    acc_id = data.get("inj_acc_id")
    mode = data.get("inj_mode", "sni")
    bug_val = msg.text.strip().replace("http://", "").replace("https://", "").split("/")[0]
    await state.clear()
    if not bug_val:
        bug_val = get_setting("bug_host", "v.whatsapp.net")
    with db_conn() as conn:
        conn.execute("UPDATE accounts SET custom_bug=?, bug_mode=? WHERE id=?", (bug_val, mode, acc_id))
        conn.commit()
    await render_injected_config_screen(msg, acc_id, mode, bug_val, is_message=True)

@router.callback_query(F.data.startswith("inj_render:"))
async def cb_inj_render(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    _, acc_id_str, mode = cb.data.split(":")
    acc_id = int(acc_id_str)
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc:
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        bug_val = acc["custom_bug"] if "custom_bug" in acc.keys() and acc["custom_bug"] else get_setting("bug_host", "v.whatsapp.net")
        conn.execute("UPDATE accounts SET bug_mode=? WHERE id=?", (mode, acc_id))
        conn.commit()
    await render_injected_config_screen(cb, acc_id, mode, bug_val, is_message=False)

async def render_injected_config_screen(msg_or_cb, acc_id: int, mode: str, bug_val: str, is_message: bool = False):
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc:
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()

    text_out, _, _, _, _, _ = engine.build_inject_links_and_yaml(
        acc["protocol"], acc["username"], acc["secret"], srv["name"], srv["host"], bug_val, mode
    )

    lbl_w = "✅ Wildcard" if mode == "wildcard" else "🌐 Wildcard"
    lbl_s = "✅ SNI" if mode == "sni" else "🔄 SNI"
    lbl_c = "✅ CDN" if mode == "cdn" else "☁️ CDN"

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📦 Sing-box (JSON)", callback_data=f"inj_extra:{acc_id}:singbox"),
            InlineKeyboardButton(text="📱 QR TLS", callback_data=f"inj_extra:{acc_id}:qrtls"),
            InlineKeyboardButton(text="📱 QR NTLS", callback_data=f"inj_extra:{acc_id}:qrntls")
        ],
        [
            InlineKeyboardButton(text=lbl_w, callback_data=f"inj_render:{acc_id}:wildcard"),
            InlineKeyboardButton(text=lbl_s, callback_data=f"inj_render:{acc_id}:sni"),
            InlineKeyboardButton(text=lbl_c, callback_data=f"inj_render:{acc_id}:cdn")
        ],
        [
            InlineKeyboardButton(text="🔗 Link Subscription (Auto-Update)", callback_data=f"inj_extra:{acc_id}:sub")
        ],
        [
            InlineKeyboardButton(text="🎯 Ganti Bug Lain", callback_data=f"inj_menu:{acc_id}"),
            InlineKeyboardButton(text="⬅️ Kembali ke Akun", callback_data=f"view_my:{acc_id}")
        ]
    ])

    if is_message:
        await msg_or_cb.answer(text_out, parse_mode="HTML", reply_markup=kb)
    else:
        await safe_edit_Basic(msg_or_cb, text_out, reply_markup=kb)

@router.callback_query(F.data.startswith("inj_extra:"))
async def cb_inj_extra(cb: CallbackQuery):
    _, acc_id_str, action = cb.data.split(":")
    acc_id = int(acc_id_str)
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc:
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()

    bug_val = acc["custom_bug"] if "custom_bug" in acc.keys() and acc["custom_bug"] else get_setting("bug_host", "v.whatsapp.net")
    mode = acc["bug_mode"] if "bug_mode" in acc.keys() and acc["bug_mode"] else "sni"
    domain = srv["host"]
    uname = acc["username"]

    _, tls_link, ntls_link, _, _, _ = engine.build_inject_links_and_yaml(
        acc["protocol"], uname, acc["secret"], srv["name"], domain, bug_val, mode
    )

    if action == "singbox":
        sb_json = engine.build_singbox_json(acc["protocol"], uname, acc["secret"], domain, bug_val, mode)
        await cb.message.answer(
            f"📦 <b>SING-BOX CONFIG (JSON) — {html.escape(uname)}</b>\n"
            f"<pre><code class=\"language-JSON\">{html.escape(sb_json)}</code></pre>",
            parse_mode="HTML"
        )
        await cb.answer("✅ Config Sing-box (JSON) dikirim!")
    elif action == "sub":
        sub_https = f"https://{domain}/sub/{uname}"
        sub_http = f"http://{domain}/sub/{uname}"
        await cb.message.answer(
            f"🔗 <b>LINK SUBSCRIPTION (AUTO-UPDATE) — {html.escape(uname)}</b>\n"
            "────────────────────────────\n"
            "• <b>HTTPS (Port 443):</b>\n"
            f"<pre><code class=\"language-Https\">{html.escape(sub_https)}</code></pre>\n\n"
            "• <b>HTTP (Port 80):</b>\n"
            f"<pre><code class=\"language-Http\">{html.escape(sub_http)}</code></pre>\n"
            "<i>Tempelkan link di atas pada v2rayNG, NekoBox, Hiddify, atau Clash untuk sinkronisasi otomatis.</i>",
            parse_mode="HTML"
        )
        await cb.answer("✅ Link Subscription dikirim!")
    elif action in ("qrtls", "qrntls"):
        target_link = tls_link if action == "qrtls" else ntls_link
        label_qr = "TLS (Port 443)" if action == "qrtls" else "NTLS (Port 80)"
        qr_path = f"/tmp/qr_{acc_id}_{action}.png"
        p = subprocess.Popen(["qrencode", "-s", "8", "-m", "2", "-o", qr_path], stdin=subprocess.PIPE, text=True)
        p.communicate(target_link)
        if os.path.exists(qr_path):
            await cb.message.answer_photo(
                photo=FSInputFile(qr_path),
                caption=f"📱 <b>QR CODE {label_qr} — {html.escape(uname)} ({acc['protocol'].upper()})</b>\n<pre><code>{html.escape(target_link)}</code></pre>",
                parse_mode="HTML"
            )
            os.remove(qr_path)
            await cb.answer(f"✅ QR {label_qr} dikirim!")
        else:
            await cb.answer("❌ Gagal membuat gambar QR.", show_alert=True)


# ==============================================================================
# FITUR BARU 3: MENU LIST WILDCARD (MURNI TANPA DOMAIN)
# ==============================================================================
@router.callback_query(F.data == "list_wildcard_menu")
async def cb_list_wildcard_menu(cb: CallbackQuery):
    presets = get_bug_presets_list()
    lines = [
        "🌐 <b>DAFTAR BUG &amp; WILDCARD SUPPORT (TANPA DOMAIN)</b>",
        "────────────────────────────",
        "<i>Ketuk pada salah satu bug di bawah untuk menyalin:</i>\n"
    ]
    for idx, b in enumerate(presets, 1):
        lines.append(f"{idx}. <code>{html.escape(b)}</code>")
    lines.append("\n────────────────────────────")
    lines.append("💡 <i>Gunakan daftar di atas pada menu <b>🎯 Inject Bug</b> atau <b>💉 Inject Akun Luar</b>.</i>")

    kb_rows = [
        [InlineKeyboardButton(text="💉 Inject Akun Luar", callback_data="ext_inject_start")],
        [InlineKeyboardButton(text="🏠 Kembali ke Menu Utama", callback_data="back_home")]
    ]
    if cb.from_user.id == ADMIN_ID:
        kb_rows.insert(1, [InlineKeyboardButton(text="🐞 Kelola Preset Bug (Admin)", callback_data="adm_bugs_menu")])
    await safe_edit_Basic(cb, "\n".join(lines), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows))

# ==============================================================================
# FITUR BARU 4: KELOLA PRESET BUG (TAMBAH & HAPUS BUG DI PANEL ADMIN)
# ==============================================================================
@router.callback_query(F.data == "adm_bugs_menu")
async def cb_adm_bugs_menu(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM bug_presets ORDER BY id ASC").fetchall()
    lines = [
        "🐞 <b>KELOLA PRESET BUG &amp; LIST WILDCARD</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"• Bug Default Utama: <code>{html.escape(get_setting('bug_host', 'v.whatsapp.net'))}</code>",
        "• Daftar Preset Bug Aktif (Muncul di List Wildcard &amp; Inject Bug):\n"
    ]
    kb = [[InlineKeyboardButton(text="➕ Tambah Bug Baru", callback_data="bug_act:add")]]
    for r in rows:
        lines.append(f"  • <code>{html.escape(r['bug_host'])}</code>")
        kb.append([
            InlineKeyboardButton(text=f"⭐ Jadikan Default ({r['bug_host'][:16]})", callback_data=f"bug_act:def:{r['id']}"),
            InlineKeyboardButton(text="🗑 Hapus", callback_data=f"bug_act:del:{r['id']}")
        ])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, "\n".join(lines), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("bug_act:"))
async def cb_bug_act(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    parts = cb.data.split(":")
    act = parts[1]
    if act == "add":
        await state.set_state(FormState.admin_add_bug_preset)
        await safe_edit_Basic(
            cb,
            "➕ <b>TAMBAH PRESET BUG BARU</b>\n"
            "────────────────────────────\n"
            "Kirimkan satu atau beberapa <b>Domain / Host / IP Bug</b> (tanpa domain server).\n"
            "<i>Tips: Anda bisa mengirim banyak bug sekaligus dipisahkan dengan baris baru (Enter) atau koma.</i>",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_bugs_menu")]])
        )
    elif act == "del":
        bid = int(parts[2])
        with db_conn() as conn:
            conn.execute("DELETE FROM bug_presets WHERE id=?", (bid,))
            conn.commit()
        await cb.answer("🗑 Bug berhasil dihapus!", show_alert=True)
        await cb_adm_bugs_menu(cb, state)
    elif act == "def":
        bid = int(parts[2])
        with db_conn() as conn:
            row = conn.execute("SELECT bug_host FROM bug_presets WHERE id=?", (bid,)).fetchone()
            if row:
                set_setting("bug_host", row["bug_host"])
        await cb.answer("✅ Diatur sebagai Bug Default!", show_alert=True)
        await cb_adm_bugs_menu(cb, state)

@router.message(FormState.admin_add_bug_preset)
async def msg_admin_add_bug_preset(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    raw = msg.text.replace(",", "\n")
    items = [x.strip().replace("http://", "").replace("https://", "").split("/")[0] for x in raw.splitlines() if x.strip()]
    added = 0
    with db_conn() as conn:
        for it in items:
            conn.execute("INSERT OR IGNORE INTO bug_presets (bug_host) VALUES (?)", (it,))
            added += 1
        conn.commit()
    await state.clear()
    await msg.answer(f"✅ Berhasil menambahkan <b>{added} Preset Bug</b> ke dalam sistem!", parse_mode="HTML", reply_markup=admin_menu_kb())

# ==============================================================================
# FITUR BARU 5: INJECT AKUN LUAR (STATELESS / TIDAK PERNAH SIMPAN AKUN APAPUN)
# ==============================================================================
@router.callback_query(F.data == "ext_inject_start")
async def cb_ext_inject_start(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    await state.set_state(FormState.ext_input_link)
    txt = (
        "💉 <b>INJECT AKUN LUAR (VMESS / VLESS / TROJAN)</b>\n"
        "────────────────────────────\n"
        "Silakan tempel &amp; kirimkan link akun luar Anda (<code>vmess://...</code>, <code>vless://...</code>, atau <code>trojan://...</code>).\n\n"
        "🔒 <b>Jaminan Privasi (Zero-Save):</b>\n"
        "<i>Bot ini TIDAK PERNAH menyimpan akun luar Anda ke database maupun log server. Konfigurasi hanya diproses seketika di memori untuk menghasilkan racikan Inject Bug &amp; Multi-Client.</i>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🏠 Batal / Menu Utama", callback_data="back_home")]])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.message(FormState.ext_input_link)
async def msg_ext_input_link(msg: Message, state: FSMContext):
    raw_link = (msg.text or "").strip()
    try:
        parsed = engine.parse_external_vpn_link(raw_link)
    except Exception as e:
        await msg.answer(
            f"⚠️ <b>Gagal membaca link akun:</b> <code>{html.escape(str(e))}</code>\n"
            "Pastikan Anda mengirimkan link utuh yang diawali <code>vmess://</code>, <code>vless://</code>, atau <code>trojan://</code>:",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🏠 Batal", callback_data="back_home")]])
        )
        return

    # Simpan di memori FSM sementara (tidak pernah menyentuh SQLite/disk)
    await state.update_data(ext_acc=parsed)
    uname = parsed["username"]
    proto = parsed["protocol"].upper()
    domain = parsed["host"]

    txt = (
        f"🎯 <b>Pilih Metode Inject Bug (Akun Luar) — {html.escape(uname)} ({proto})</b>\n"
        f"🌐 <b>Server Akun:</b> <code>{html.escape(domain)}</code>\n"
        "🔒 <i>Status: Diproses di RAM (Tanpa Simpan Database)</i>\n\n"
        "Silakan pilih metode pemasangan bug yang ingin Anda gunakan:\n"
        "1️⃣ <b>Wildcard (bug.domain):</b> <code>Address = bug, SNI &amp; Host = bug.domain</code>\n"
        "2️⃣ <b>SNI / SSL (Spoof):</b> <code>Address = domain, SNI &amp; Host = bug</code>\n"
        "3️⃣ <b>CDN / Direct WS:</b> <code>Address = bug, SNI &amp; Host = domain</code>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="1️⃣ Mode Wildcard (bug.domain)", callback_data="ext_mode:wildcard")],
        [InlineKeyboardButton(text="2️⃣ Mode SNI / SSL (Spoof Bug)", callback_data="ext_mode:sni")],
        [InlineKeyboardButton(text="3️⃣ Mode CDN / WS (Direct)", callback_data="ext_mode:cdn")],
        [InlineKeyboardButton(text="⚡ Tampilkan Tanpa Bug (Default)", callback_data="ext_render:default")],
        [InlineKeyboardButton(text="🏠 Kembali ke Menu Utama", callback_data="back_home")]
    ])
    await msg.answer(txt, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("ext_mode:"))
async def cb_ext_pickmode(cb: CallbackQuery, state: FSMContext):
    mode = cb.data.split(":")[1]
    data = await state.get_data()
    if not data.get("ext_acc"):
        await cb.answer("⚠️ Sesi memori selesai, silakan kirim ulang link akun luar Anda.", show_alert=True)
        await cb_ext_inject_start(cb, state)
        return

    await state.update_data(ext_mode=mode)
    await state.set_state(FormState.ext_input_bug)

    presets = get_bug_presets_list()
    kb_rows = [
        [InlineKeyboardButton(text="✍️ Ketik Bug Sendiri (Langsung Kirim Pesan)", callback_data="ext_manual_hint")]
    ]
    row_tmp = []
    for b in presets:
        row_tmp.append(InlineKeyboardButton(text=f"🐞 {b}", callback_data=f"ext_bug:{b}"))
        if len(row_tmp) == 2:
            kb_rows.append(row_tmp)
            row_tmp = []
    if row_tmp:
        kb_rows.append(row_tmp)
    kb_rows.append([InlineKeyboardButton(text="🏠 Kembali ke Menu Utama", callback_data="back_home")])

    await safe_edit_Basic(
        cb,
        f"🎯 <b>PILIH ATAU KETIK BUG ({mode.upper()}) — AKUN LUAR</b>\n"
        "────────────────────────────\n"
        "• Klik salah satu tombol <b>Preset Bug</b> di bawah, ATAU\n"
        "• Langsung <b>ketik Domain / IP Bug</b> Anda sendiri ke chat ini:",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows)
    )

@router.callback_query(F.data == "ext_manual_hint")
async def cb_ext_manual_hint(cb: CallbackQuery):
    await cb.answer("✍️ Silakan langsung ketik dan kirimkan Domain / IP Bug Anda di kolom chat bawah!", show_alert=True)

@router.callback_query(F.data.startswith("ext_bug:"))
async def cb_ext_setbug(cb: CallbackQuery, state: FSMContext):
    bug_val = cb.data.split(":", 1)[1]
    data = await state.get_data()
    ext_acc = data.get("ext_acc")
    mode = data.get("ext_mode", "sni")
    if not ext_acc:
        await cb.answer("⚠️ Sesi memori selesai, silakan kirim ulang link akun luar Anda.", show_alert=True)
        await cb_ext_inject_start(cb, state)
        return
    await state.update_data(ext_bug=bug_val)
    await render_external_injected(cb, ext_acc, mode, bug_val, is_message=False)

@router.message(FormState.ext_input_bug)
async def msg_ext_input_bug(msg: Message, state: FSMContext):
    data = await state.get_data()
    ext_acc = data.get("ext_acc")
    mode = data.get("ext_mode", "sni")
    if not ext_acc:
        await state.clear()
        await msg.answer("⚠️ Sesi memori selesai, silakan ulangi dari menu utama.", reply_markup=main_menu_kb(msg.from_user.id))
        return
    bug_val = msg.text.strip().replace("http://", "").replace("https://", "").split("/")[0]
    await state.update_data(ext_bug=bug_val)
    await render_external_injected(msg, ext_acc, mode, bug_val, is_message=True)

@router.callback_query(F.data.startswith("ext_render:"))
async def cb_ext_render_switch(cb: CallbackQuery, state: FSMContext):
    mode = cb.data.split(":")[1]
    data = await state.get_data()
    ext_acc = data.get("ext_acc")
    if not ext_acc:
        await cb.answer("⚠️ Sesi memori telah dibersihkan demi keamanan. Silakan tempel ulang link Anda.", show_alert=True)
        await cb_ext_inject_start(cb, state)
        return
    bug_val = data.get("ext_bug") or get_setting("bug_host", "v.whatsapp.net")
    await state.update_data(ext_mode=mode)
    await render_external_injected(cb, ext_acc, mode, bug_val, is_message=False)

@router.callback_query(F.data == "ext_singbox")
async def cb_ext_singbox(cb: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    ext_acc = data.get("ext_acc")
    if not ext_acc:
        await cb.answer("⚠️ Sesi memori telah selesai.", show_alert=True)
        return
    mode = data.get("ext_mode", "sni")
    bug_val = data.get("ext_bug") or get_setting("bug_host", "v.whatsapp.net")
    sb_json = engine.build_singbox_json(ext_acc["protocol"], ext_acc["username"], ext_acc["secret"], ext_acc["host"], bug_val, mode)
    await cb.message.answer(
        f"📦 <b>SING-BOX CONFIG (JSON) — {html.escape(ext_acc['username'])}</b>\n"
        f"<pre><code class=\"language-JSON\">{html.escape(sb_json)}</code></pre>",
        parse_mode="HTML"
    )
    await cb.answer("✅ Config Sing-box dikirim!")

async def render_external_injected(msg_or_cb, ext_acc: dict, mode: str, bug_val: str, is_message: bool = False):
    text_out, _, _, _, _, _ = engine.build_inject_links_and_yaml(
        ext_acc["protocol"], ext_acc["username"], ext_acc["secret"], "External Server (No-Save)", ext_acc["host"], bug_val, mode
    )
    lbl_w = "✅ Wildcard" if mode == "wildcard" else "🌐 Wildcard"
    lbl_s = "✅ SNI" if mode == "sni" else "🔄 SNI"
    lbl_c = "✅ CDN" if mode == "cdn" else "☁️ CDN"

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text=lbl_w, callback_data="ext_render:wildcard"),
            InlineKeyboardButton(text=lbl_s, callback_data="ext_render:sni"),
            InlineKeyboardButton(text=lbl_c, callback_data="ext_render:cdn")
        ],
        [
            InlineKeyboardButton(text="📦 Sing-box (JSON)", callback_data="ext_singbox"),
            InlineKeyboardButton(text="🎯 Ganti Bug", callback_data=f"ext_mode:{mode}")
        ],
        [
            InlineKeyboardButton(text="💉 Inject Akun Luar Lainnya", callback_data="ext_inject_start"),
            InlineKeyboardButton(text="🏠 Menu Utama", callback_data="back_home")
        ]
    ])
    if is_message:
        await msg_or_cb.answer(text_out, parse_mode="HTML", reply_markup=kb)
    else:
        await safe_edit_Basic(msg_or_cb, text_out, reply_markup=kb)

# ==============================================================================
# FITUR BARU 6: BROADCAST TEKS / FOTO KE SELURUH PENGGUNA BOT
# ==============================================================================
@router.callback_query(F.data == "adm_broadcast_menu")
async def cb_adm_broadcast_menu(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.set_state(FormState.admin_broadcast_msg)
    with db_conn() as conn:
        u1 = [r["user_id"] for r in conn.execute("SELECT user_id FROM users").fetchall()]
        u2 = [r["user_id"] for r in conn.execute("SELECT DISTINCT user_id FROM accounts").fetchall()]
    total_targets = len(set(u1 + u2))
    txt = (
        "📣 <b>BROADCAST PESAN KE SELURUH USER BOT</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• Total Penerima Terdaftar: <b>{total_targets} User</b>\n\n"
        "Silakan kirimkan <b>Pesan Teks</b> ATAU <b>Foto + Caption</b> yang ingin Anda sebarkan ke seluruh pengguna bot:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="admin_home")]])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.message(FormState.admin_broadcast_msg)
async def msg_admin_broadcast_exec(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    await state.clear()
    with db_conn() as conn:
        u1 = [r["user_id"] for r in conn.execute("SELECT user_id FROM users").fetchall()]
        u2 = [r["user_id"] for r in conn.execute("SELECT DISTINCT user_id FROM accounts").fetchall()]
    targets = sorted(list(set(u1 + u2)))

    status_msg = await msg.answer(f"⏳ <b>Mengirimkan Broadcast ke {len(targets)} pengguna...</b>", parse_mode="HTML")
    sent_ok = 0
    sent_fail = 0

    for uid in targets:
        try:
            if msg.photo:
                fid = msg.photo[-1].file_id
                cap = msg.html_text if hasattr(msg, "html_text") and msg.html_text else (msg.caption or "")
                await bot.send_photo(chat_id=uid, photo=fid, caption=cap, parse_mode="HTML")
            else:
                txt = msg.html_text if hasattr(msg, "html_text") and msg.html_text else (msg.text or "")
                await bot.send_message(chat_id=uid, text=txt, parse_mode="HTML")
            sent_ok += 1
        except Exception:
            sent_fail += 1
        await asyncio.sleep(0.05)

    log_activity("BROADCAST", f"Terkirim: {sent_ok}, Gagal: {sent_fail}")
    await status_msg.edit_text(
        f"✅ <b>BROADCAST SELESAI!</b>\n"
        "────────────────────────────\n"
        f"• Berhasil Terkirim : <b>{sent_ok} User</b>\n"
        f"• Gagal / Blokir Bot : <b>{sent_fail} User</b>",
        parse_mode="HTML",
        reply_markup=admin_menu_kb()
    )


# ==============================================================================
# FITUR TUKAR PROTOKOL (KHUSUS VMESS, VLESS, TROJAN) & PINDAH SERVER (SEMUA AKUN)
# ==============================================================================
@router.callback_query(F.data.startswith("chg_proto_menu:"))
async def cb_chg_proto_menu(cb: CallbackQuery):
    acc_id = int(cb.data.split(":")[1])
    now = int(time.time())
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if acc["locked_until"] > now and cb.from_user.id != ADMIN_ID:
            await cb.answer("⛔ Akun sedang TERKUNCI karena multi-login dan tidak dapat diubah!", show_alert=True)
            return
        if acc["protocol"] not in ("vmess", "vless", "trojan"):
            await cb.answer("⚠️ Akun SSH tidak dapat menukar protokol (hanya bisa Pindah Server).", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()

    cur_p = acc["protocol"]
    txt = (
        f"🔄 <b>TUKAR PROTOKOL XRAY — {html.escape(acc['username'])}</b>\n"
        "────────────────────────────\n"
        f"• <b>Server Saat Ini</b>   : {html.escape(srv['name'])} (<code>{html.escape(srv['host'])}</code>)\n"
        f"• <b>Protokol Saat Ini</b> : <b>{cur_p.upper()}</b>\n"
        f"• <b>UUID / Key</b>        : <code>{html.escape(acc['secret'])}</code>\n\n"
        "Silakan pilih protokol tujuan (UUID &amp; masa aktif tetap sama):"
    )
    kb_rows = []
    for p, label in (("vmess", "⚡ VMESS"), ("vless", "💎 VLESS"), ("trojan", "🛡️ TROJAN")):
        if p == cur_p:
            kb_rows.append([InlineKeyboardButton(text=f"✅ {label} (Aktif Saat Ini)", callback_data="noop_proto")])
        else:
            kb_rows.append([InlineKeyboardButton(text=f"🔄 Ubah ke {label}", callback_data=f"do_chg_proto:{acc_id}:{p}")])
    kb_rows.append([
        InlineKeyboardButton(text="⬅️ Kembali ke Detail Akun", callback_data=f"view_my:{acc_id}"),
        InlineKeyboardButton(text="👤 Akun Saya", callback_data="my_accounts")
    ])
    await safe_edit_Basic(cb, txt, reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows))

@router.callback_query(F.data == "noop_proto")
async def cb_noop_proto(cb: CallbackQuery):
    await cb.answer("Ini adalah protokol/server Anda saat ini.", show_alert=False)

@router.callback_query(F.data.startswith("do_chg_proto:"))
async def cb_do_chg_proto(cb: CallbackQuery):
    _, acc_id_str, new_proto = cb.data.split(":")
    acc_id = int(acc_id_str)
    now = int(time.time())
    if new_proto not in ("vmess", "vless", "trojan"):
        return

    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if acc["locked_until"] > now and cb.from_user.id != ADMIN_ID:
            await cb.answer("⛔ Akun sedang TERKUNCI karena multi-login!", show_alert=True)
            return
        if acc["protocol"] == "ssh":
            await cb.answer("⚠️ Akun SSH tidak mendukung tukar protokol.", show_alert=True)
            return
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or conn.execute("SELECT * FROM servers LIMIT 1").fetchone()

    old_proto = acc["protocol"]
    if old_proto == new_proto:
        await cb.answer("Protokol sudah sama.", show_alert=True)
        return

    await cb.answer(f"⏳ Mengubah protokol {old_proto.upper()} -> {new_proto.upper()}...")
    exp_ssh_date = datetime.fromtimestamp(acc["expired_at"]).strftime("%Y-%m-%d")

    try:
        await asyncio.to_thread(engine.remove_account_from_server, srv, old_proto, acc["username"])
        await asyncio.to_thread(engine.add_account_to_server, srv, new_proto, acc["username"], acc["secret"], exp_ssh_date)
    except Exception as e:
        await cb.message.answer(f"❌ Gagal mengubah protokol di server: <code>{html.escape(str(e))}</code>", parse_mode="HTML")
        return

    with db_conn() as conn:
        conn.execute("UPDATE accounts SET protocol=? WHERE id=?", (new_proto, acc_id))
        conn.commit()
        updated_acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()

    log_activity("CHANGE_PROTO", f"{acc['username']} tukar protokol {old_proto.upper()} -> {new_proto.upper()}")
    out_html, kb = build_account_details_and_kb(updated_acc, srv, back_target="my_accounts")
    await safe_edit_Basic(
        cb,
        f"✅ <b>Protokol berhasil diubah dari {old_proto.upper()} ke {new_proto.upper()}!</b>\n\n{out_html}",
        reply_markup=kb
    )

@router.callback_query(F.data.startswith("move_srv_menu:"))
async def cb_move_srv_menu(cb: CallbackQuery):
    acc_id = int(cb.data.split(":")[1])
    now = int(time.time())
    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if acc["locked_until"] > now and cb.from_user.id != ADMIN_ID:
            await cb.answer("⛔ Akun sedang TERKUNCI karena multi-login dan tidak dapat dipindah server!", show_alert=True)
            return
        srvs = conn.execute("SELECT * FROM servers ORDER BY id ASC").fetchall()
        cur_srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone() or srvs[0]

    default_max_u = get_int_setting("max_users_per_vps", 100, 1)
    txt = (
        f"🌐 <b>PINDAH SERVER VPS — {html.escape(acc['username'])} ({acc['protocol'].upper()})</b>\n"
        "────────────────────────────\n"
        f"• <b>Server Saat Ini</b> : {html.escape(cur_srv['name'])} (<code>{html.escape(cur_srv['host'])}</code>)\n\n"
        "Silakan pilih server VPS tujuan di bawah ini:"
    )
    kb_rows = []
    for s in srvs:
        with db_conn() as conn:
            cnt = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (s["id"], now)).fetchone()["c"]
        max_u = s["max_users"] if "max_users" in s.keys() and s["max_users"] else default_max_u
        if s["id"] == acc["server_id"]:
            kb_rows.append([InlineKeyboardButton(text=f"✅ {s['name']} ({s['city']}) — [{cnt}/{max_u}] (Saat Ini)", callback_data="noop_proto")])
        else:
            kb_rows.append([InlineKeyboardButton(text=f"🌐 Pindah ke {s['name']} ({s['city']}) — [{cnt}/{max_u}]", callback_data=f"do_move_srv:{acc_id}:{s['id']}")])

    kb_rows.append([
        InlineKeyboardButton(text="⬅️ Kembali ke Detail Akun", callback_data=f"view_my:{acc_id}"),
        InlineKeyboardButton(text="👤 Akun Saya", callback_data="my_accounts")
    ])
    await safe_edit_Basic(cb, txt, reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows))

@router.callback_query(F.data.startswith("do_move_srv:"))
async def cb_do_move_srv(cb: CallbackQuery):
    _, acc_id_str, target_sid_str = cb.data.split(":")
    acc_id = int(acc_id_str)
    target_sid = int(target_sid_str)
    now = int(time.time())

    with db_conn() as conn:
        acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        if not acc or (cb.from_user.id != ADMIN_ID and acc["user_id"] != cb.from_user.id):
            await cb.answer("Akun tidak ditemukan.", show_alert=True)
            return
        if acc["locked_until"] > now and cb.from_user.id != ADMIN_ID:
            await cb.answer("⛔ Akun sedang TERKUNCI karena multi-login dan tidak dapat dipindah server!", show_alert=True)
            return
        if acc["server_id"] == target_sid:
            await cb.answer("Akun sudah berada di server ini.", show_alert=True)
            return
        old_srv = conn.execute("SELECT * FROM servers WHERE id=?", (acc["server_id"],)).fetchone()
        new_srv = conn.execute("SELECT * FROM servers WHERE id=?", (target_sid,)).fetchone()
        if not new_srv:
            await cb.answer("Server tujuan tidak ditemukan.", show_alert=True)
            return
        cnt = conn.execute("SELECT COUNT(*) as c FROM accounts WHERE server_id=? AND expired_at > ?", (target_sid, now)).fetchone()["c"]

    max_u = new_srv["max_users"] if "max_users" in new_srv.keys() and new_srv["max_users"] else get_int_setting("max_users_per_vps", 100, 1)
    if cnt >= max_u and cb.from_user.id != ADMIN_ID:
        await cb.answer(f"⚠️ Server tujuan penuh ({cnt}/{max_u} akun aktif)!", show_alert=True)
        return

    await cb.answer(f"⏳ Memindahkan akun ke {new_srv['name']}...")
    exp_ssh_date = datetime.fromtimestamp(acc["expired_at"]).strftime("%Y-%m-%d")

    try:
        await asyncio.to_thread(engine.add_account_to_server, new_srv, acc["protocol"], acc["username"], acc["secret"], exp_ssh_date)
        if old_srv:
            await asyncio.to_thread(engine.remove_account_from_server, old_srv, acc["protocol"], acc["username"])
    except Exception as e:
        await cb.message.answer(f"❌ Gagal memindahkan akun ke {html.escape(new_srv['name'])}: <code>{html.escape(str(e))}</code>", parse_mode="HTML")
        return

    with db_conn() as conn:
        conn.execute("UPDATE accounts SET server_id=? WHERE id=?", (target_sid, acc_id))
        conn.commit()
        updated_acc = conn.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()

    log_activity("MOVE_SERVER", f"{acc['username']} ({acc['protocol'].upper()}) pindah ke {new_srv['name']}")
    out_html, kb = build_account_details_and_kb(updated_acc, new_srv, back_target="my_accounts")
    await safe_edit_Basic(
        cb,
        f"✅ <b>Akun berhasil dipindahkan ke {html.escape(new_srv['name'])} (<code>{html.escape(new_srv['host'])}</code>)!</b>\n\n{out_html}",
        reply_markup=kb
    )


# ==============================================================================
# FITUR V11: PRO BUG SCANNER ISP, CHANGE DOMAIN, TEMA BOT & AUTO-HEAL MONITOR
# ==============================================================================
SCAN_COOLDOWN_MAP = {}

@router.callback_query(F.data == "bug_scanner_start")
async def cb_bug_scanner_start(cb: CallbackQuery, state: FSMContext):
    allowed, reason = check_user_access(cb.from_user.id)
    if not allowed:
        await cb.answer(reason, show_alert=True)
        return
    await state.clear()
    await state.set_state(FormState.user_bug_scanner)
    txt = (
        "🔍 <b>PRO BUG &amp; PAYLOAD SCANNER ISP</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Fitur ini menguji secara langsung apakah suatu Domain / IP Bug dapat tembus WebSocket 101 Switching Protocols ke server VPN bot ini, memeriksa ASN, Ping, serta membongkar Subdomain SSL (SANs).\n\n"
        "🛡 <b>Aturan Anti-Spam:</b>\n"
        "• <b>Mode Bulk Scan (Multi-Bug):</b>\n"
        "🟢 <b>Aktif</b>\n"
        "(Kirim hingga 6 domain sekaligus dipisahkan spasi/enter).\n"
        "• <b>Jeda Cooldown User:</b>\n"
        "<code>20 Detik / Scan</code>\n"
        "📌 <b>Ketik 1 atau beberapa Domain / IP Bug sekarang:</b>\n"
        "Contoh:\n"
        "<code>quiz.vidio.com</code>\n"
        "atau daftar bug ke bawah."
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🌐 Lihat List Wildcard", callback_data="list_wildcard_menu")],
        [InlineKeyboardButton(text="🏠 Kembali ke Menu Utama", callback_data="back_home")]
    ])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

def format_single_pro_scan_html(r: dict, vpn_dom: str) -> str:
    h = html.escape
    bug = r["bug"]
    sans_list = r.get("sans", [])
    sans_str = ", ".join([f"<code>{h(s)}</code>" for s in sans_list]) if sans_list else "<i>Tidak ditemukan</i>"

    if r.get("is_cf"):
        rec_wc = "• ✅ <b>WILDCARD:</b> Cocok! (Berada di jaringan Cloudflare)."
    elif r.get("wildcard_101_ok"):
        rec_wc = "• ✅ <b>WILDCARD:</b> Cocok! (Handshake Wildcard Tembus)."
    else:
        rec_wc = "• ⚠️ <b>WILDCARD:</b> Kurang cocok (Bukan jaringan Cloudflare)."

    if r.get("cdn_101_ok"):
        rec_cdn = "• ✅ <b>CDN DIRECT:</b> 100% TEMBUS (101 WS OK) sebagai Address!"
    else:
        rec_cdn = "• ⚠️ <b>CDN DIRECT:</b> Tidak tembus 101 langsung sebagai Address."

    if r.get("ssl_ok"):
        rec_sni = f"• ✅ <b>SNI / SSL:</b> 100% Cocok! Gunakan SNI = <code>{h(bug)}</code>."
    else:
        rec_sni = "• ❌ <b>SNI / SSL:</b> Handshake SSL Port 443 tidak merespons."

    return (
        "🔍 <b>HASIL PRO SCAN BUG &amp; SIMULASI PAYLOAD</b>\n"
        "────────────────────────────\n"
        f"🌐 <b>Host / Bug:</b> <code>{h(bug)}</code>\n"
        f"📡 <b>IPv4 Address:</b> <code>{h(r['ips_str'])}</code>\n"
        f"🏢 <b>Jaringan ASN:</b> <code>{h(r['asn_str'])}</code> (⚡ <code>{h(r['ping_ms'])}</code>)\n"
        f"🖥 <b>Server Header:</b> <code>{h(r['server_hdr'])}</code>\n"
        f"🛡 <b>Status CDN:</b> {r['cdn_status']}\n"
        f"🔐 <b>Info SSL/TLS:</b> <code>{h(r['ssl_info'])}</code>\n"
        f"🧩 <b>Subdomain SSL:</b> {sans_str}\n\n"
        f"🧪 <b>[ SIMULASI PAYLOAD KE {h(vpn_dom.upper())} ]</b>\n"
        f"• <b>HTTP Biasa (80):</b> {r['http_80']}\n"
        f"• <b>HTTPS / TLS (443):</b> {r['https_443']}\n"
        f"• <b>Tes WS Wildcard:</b> {r['ws_wildcard']}\n"
        f"• <b>Tes WS Direct CDN:</b> {r['ws_direct_cdn']}\n"
        "────────────────────────────\n"
        "💡 <b>Kesimpulan &amp; Rekomendasi:</b>\n"
        f"{rec_wc}\n"
        f"{rec_cdn}\n"
        f"{rec_sni}"
    )

def build_pro_scan_kb(bug: str) -> InlineKeyboardMarkup:
    b_safe = bug[:38]
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="⚡ Langsung Inject (WILDCARD)", callback_data=f"scan_inj:wildcard:{b_safe}"),
            InlineKeyboardButton(text="🛠 Inject Config Luar", callback_data="ext_inject_start")
        ],
        [
            InlineKeyboardButton(text="➕ Simpan Wildcard", callback_data=f"scan_save:wildcard:{b_safe}"),
            InlineKeyboardButton(text="➕ Simpan SNI", callback_data=f"scan_save:sni:{b_safe}"),
            InlineKeyboardButton(text="➕ Simpan CDN", callback_data=f"scan_save:cdn:{b_safe}")
        ],
        [
            InlineKeyboardButton(text="🔍 Scan Bug Lain", callback_data="bug_scanner_start"),
            InlineKeyboardButton(text="🏠 Menu Utama", callback_data="back_home")
        ]
    ])

@router.message(FormState.user_bug_scanner)
async def msg_user_bug_scanner_exec(msg: Message, state: FSMContext):
    uid = msg.from_user.id
    now = time.time()
    if uid != ADMIN_ID:
        last_scan = SCAN_COOLDOWN_MAP.get(uid, 0)
        rem = int(20 - (now - last_scan))
        if rem > 0:
            await msg.answer(f"⏳ <b>Cooldown Anti-Spam Aktif!</b>\nSilakan tunggu <b>{rem} detik</b> lagi sebelum melakukan scan berikutnya.", parse_mode="HTML")
            return
        SCAN_COOLDOWN_MAP[uid] = now

    raw_text = (msg.text or "").replace(",", " ").replace(";", " ")
    tokens = [t.strip() for t in raw_text.split() if t.strip()]
    if not tokens:
        await msg.answer("⚠️ Harap ketik minimal 1 Domain atau IP Bug.")
        return

    targets = []
    for t in tokens:
        clean_t = t.replace("http://", "").replace("https://", "").split("/")[0]
        if clean_t and clean_t not in targets:
            targets.append(clean_t)
        if len(targets) >= 6:
            break

    await state.clear()
    vpn_dom = get_current_main_domain()
    wait_msg = await msg.answer(
        f"🔍 <b>Memindai {len(targets)} Bug / Host &amp; Simulasi Payload ke <code>{html.escape(vpn_dom.upper())}</code>...</b>",
        parse_mode="HTML"
    )

    results = []
    for bug_t in targets:
        r = await asyncio.to_thread(engine.scan_single_bug_target, bug_t, vpn_dom)
        results.append(r)

    primary_bug = results[0]["bug"]
    blocks = [format_single_pro_scan_html(r, vpn_dom) for r in results]
    kb = build_pro_scan_kb(primary_bug)
    await wait_msg.edit_text("\n\n════════════════════════════\n\n".join(blocks), parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("scan_save:"))
async def cb_scan_save_bug(cb: CallbackQuery):
    _, mode, bug_val = cb.data.split(":", 2)
    now = int(time.time())
    with db_conn() as conn:
        if cb.from_user.id == ADMIN_ID:
            conn.execute("INSERT OR IGNORE INTO bug_presets (bug_host) VALUES (?)", (bug_val,))
        conn.execute(
            "UPDATE accounts SET custom_bug=?, bug_mode=? WHERE user_id=? AND expired_at > ?",
            (bug_val, mode, cb.from_user.id, now)
        )
        conn.commit()
    await cb.answer(f"✅ Bug {bug_val} berhasil disimpan ke mode {mode.upper()}!", show_alert=True)

@router.callback_query(F.data.startswith("scan_inj:"))
async def cb_scan_direct_inject(cb: CallbackQuery, state: FSMContext):
    _, mode, bug_val = cb.data.split(":", 2)
    now = int(time.time())
    with db_conn() as conn:
        accs = conn.execute(
            "SELECT * FROM accounts WHERE user_id=? AND expired_at > ? ORDER BY id DESC",
            (cb.from_user.id, now)
        ).fetchall()

    if not accs:
        await cb.answer("ℹ️ Anda belum memiliki akun di bot ini, mengarahkan ke Inject Config Luar...", show_alert=False)
        await state.update_data(ext_bug=bug_val, ext_mode=mode)
        await cb_ext_inject_start(cb, state)
        return

    if len(accs) == 1:
        acc_id = accs[0]["id"]
        with db_conn() as conn:
            conn.execute("UPDATE accounts SET custom_bug=?, bug_mode=? WHERE id=?", (bug_val, mode, acc_id))
            conn.commit()
        await render_injected_config_screen(cb, acc_id, mode, bug_val, is_message=False)
    else:
        kb_rows = []
        for a in accs:
            kb_rows.append([
                InlineKeyboardButton(
                    text=f"⚡ Inject ke {a['username']} ({a['protocol'].upper()})",
                    callback_data=f"inj_setbug:{a['id']}:{mode}:{bug_val}"
                )
            ])
        kb_rows.append([InlineKeyboardButton(text="🏠 Menu Utama", callback_data="back_home")])
        await safe_edit_Basic(
            cb,
            f"⚡ <b>LANGSUNG INJECT ({mode.upper()}) — <code>{html.escape(bug_val)}</code></b>\n"
            "────────────────────────────\n"
            "Pilih akun Anda yang ingin langsung dipasang bug ini:",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows)
        )

# --- FITUR CHANGE DOMAIN VPS (UTAMA & REMOTE) ---
@router.callback_query(F.data == "adm_chg_domain_menu")
async def cb_adm_chg_domain_menu(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    await state.clear()
    with db_conn() as conn:
        srvs = conn.execute("SELECT * FROM servers ORDER BY id ASC").fetchall()

    lines = [
        "🌐 <b>CHANGE DOMAIN SERVER VPS</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Fitur ini digunakan apabila terjadi kesalahan ketik (typo) domain saat instalasi atau ingin mengganti domain baru pada <b>Server Utama</b> maupun <b>VPS Tambahan</b>.\n\n"
        "Pilih server yang ingin diganti domainnya:"
    ]
    kb = []
    for s in srvs:
        tp = "🟢 Utama/Lokal" if s["is_local"] == 1 else "🌐 Remote VPS"
        lines.append(f"• <b>#{s['id']} {html.escape(s['name'])}</b> [{tp}]: <code>{html.escape(s['host'])}</code>")
        kb.append([InlineKeyboardButton(text=f"✏️ Ganti Domain #{s['id']} — {s['name']} ({s['host']})", callback_data=f"chg_dom_pick:{s['id']}")])

    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, "\n".join(lines), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("chg_dom_pick:"))
async def cb_chg_dom_pick(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    sid = int(cb.data.split(":")[1])
    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (sid,)).fetchone()
    if not srv:
        await cb.answer("Server tidak ditemukan.", show_alert=True)
        return
    await state.update_data(chg_dom_sid=sid)
    await state.set_state(FormState.admin_change_domain_input)
    await safe_edit_Basic(
        cb,
        f"🌐 <b>GANTI DOMAIN SERVER #{sid} — {html.escape(srv['name'])}</b>\n"
        "────────────────────────────\n"
        f"• Domain Saat Ini: <code>{html.escape(srv['host'])}</code>\n\n"
        "Silakan ketik dan kirimkan <b>Domain / Subdomain Baru</b> untuk server ini\n"
        "<i>(Sistem akan otomatis memperbarui database, Nginx, dan membuat ulang Sertifikat SSL)</i>:",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_chg_domain_menu")]])
    )

@router.message(FormState.admin_change_domain_input)
async def msg_admin_change_domain_input(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    global DEFAULT_DOMAIN
    data = await state.get_data()
    sid = data.get("chg_dom_sid", 1)
    new_dom = (msg.text or "").strip().replace("http://", "").replace("https://", "").split("/")[0]
    await state.clear()

    if not new_dom or "." not in new_dom:
        await msg.answer("⚠️ Format domain tidak valid. Silakan ulangi dari menu Change Domain.", reply_markup=admin_menu_kb())
        return

    with db_conn() as conn:
        srv = conn.execute("SELECT * FROM servers WHERE id=?", (sid,)).fetchone()
    if not srv:
        await msg.answer("❌ Server tidak ditemukan.", reply_markup=admin_menu_kb())
        return

    wait_msg = await msg.answer(
        f"⏳ <b>Mengubah domain Server #{sid} ({html.escape(srv['name'])}) menjadi <code>{html.escape(new_dom)}</code>...</b>\n"
        "<i>Memperbarui konfigurasi Nginx, Database &amp; menerbitkan Sertifikat SSL baru...</i>",
        parse_mode="HTML"
    )
    ok, info = await asyncio.to_thread(engine.change_server_domain, srv, new_dom)
    if ok:
        with db_conn() as conn:
            conn.execute("UPDATE servers SET host=? WHERE id=?", (new_dom, sid))
            conn.commit()
        if srv["is_local"] == 1:
            DEFAULT_DOMAIN = new_dom
        log_activity("CHANGE_DOMAIN", f"Server #{sid} ({srv['name']}) ubah domain ke {new_dom}")

    await wait_msg.edit_text(
        f"{'✅' if ok else '⚠️'} <b>HASIL PERUBAHAN DOMAIN:</b>\n{html.escape(info)}",
        parse_mode="HTML",
        reply_markup=admin_menu_kb()
    )

# --- FITUR GANTI TEMA TAMPILAN BOT ---
@router.callback_query(F.data == "adm_theme_menu")
async def cb_adm_theme_menu(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    cur_theme = get_setting("bot_theme", "default")
    th_obj = get_active_theme()
    txt = (
        "🎨 <b>GANTI TEMA TAMPILAN BOT</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Tema Aktif Saat Ini:</b> <b>{html.escape(th_obj['name'])}</b>\n\n"
        "<b>Preview Header Tema:</b>\n"
        f"{th_obj['title']}\n"
        f"{th_obj['line']}\n"
        f"{th_obj['bullet']} <b>Tombol Buat:</b> {th_obj['btn_create']} SSH / VMess / VLESS / Trojan\n"
        f"{th_obj['bullet']} <b>Tombol Trial:</b> {th_obj['btn_trial']} SSH / VMess / VLESS / Trojan\n"
        f"{th_obj['line']}\n\n"
        "👇 Pilih salah satu tema di bawah untuk mengganti suasana tampilan bot secara instan:"
    )
    kb_rows = []
    for k, v in THEMES_CATALOG.items():
        prefix = "✅ " if k == cur_theme else "🎨 "
        kb_rows.append([InlineKeyboardButton(text=f"{prefix}{v['name']}", callback_data=f"set_theme:{k}")])
    kb_rows.append([
        InlineKeyboardButton(text="👁 Lihat Menu Utama", callback_data="back_home"),
        InlineKeyboardButton(text="⬅️ Panel Admin", callback_data="admin_home")
    ])
    await safe_edit_Basic(cb, txt, reply_markup=InlineKeyboardMarkup(inline_keyboard=kb_rows))

@router.callback_query(F.data.startswith("set_theme:"))
async def cb_set_theme(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    t_key = cb.data.split(":")[1]
    if t_key in THEMES_CATALOG:
        set_setting("bot_theme", t_key)
        await cb.answer(f"🎨 Tema diubah ke: {THEMES_CATALOG[t_key]['name']}!", show_alert=True)
    await cb_adm_theme_menu(cb)

# --- FITUR AUTO-HEAL & NOTIFIKASI STATUS SERVER ---
@router.callback_query(F.data == "adm_autoheal_menu")
async def cb_adm_autoheal_menu(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    heal_en = "🟢 ON (Aktif)" if get_setting("auto_heal_enabled", "1") == "1" else "🔴 OFF"
    notif_en = "🟢 ON (Aktif)" if get_setting("notif_server_status", "1") == "1" else "🔴 OFF"
    txt = (
        "🩺 <b>AUTO-HEAL &amp; NOTIFIKASI STATUS SERVER</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Status Auto-Heal Daemon:</b> <b>{heal_en}</b>\n"
        f"• <b>Notifikasi Status Server:</b> <b>{notif_en}</b>\n"
        "• <b>Interval Pemindaian:</b> <code>Setiap 60 Detik</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "<b>Cara Kerja Auto-Heal:</b>\n"
        "<i>Sistem memantau Xray, Dropbear, Nginx, dan WS-Bridge di Server Utama maupun VPS Tambahan setiap menit. Jika ada layanan yang mati/crash, sistem otomatis me-restartnya dan mengirimkan laporan ke Admin &amp; Topik Grup.</i>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text=f"🩺 Auto-Heal ({heal_en})", callback_data="heal_act:toggle_heal"),
            InlineKeyboardButton(text=f"🔔 Notif Status ({notif_en})", callback_data="heal_act:toggle_notif")
        ],
        [
            InlineKeyboardButton(text="⚡ Jalankan Cek & Auto-Heal Sekarang", callback_data="heal_act:run_now")
        ],
        [
            InlineKeyboardButton(text="📢 Kirim Laporan Status Server ke Grup/DM", callback_data="heal_act:send_report")
        ],
        [InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")]
    ])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data.startswith("heal_act:"))
async def cb_heal_act(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    if act == "toggle_heal":
        cur = get_setting("auto_heal_enabled", "1")
        set_setting("auto_heal_enabled", "0" if cur == "1" else "1")
        await cb_adm_autoheal_menu(cb)
    elif act == "toggle_notif":
        cur = get_setting("notif_server_status", "1")
        set_setting("notif_server_status", "0" if cur == "1" else "1")
        await cb_adm_autoheal_menu(cb)
    elif act == "run_now":
        await cb.answer("🩺 Memeriksa & memulihkan layanan di seluruh server...")
        with db_conn() as conn:
            srvs = conn.execute("SELECT * FROM servers").fetchall()
        events = await asyncio.to_thread(engine.run_auto_heal_check, srvs)
        if not events:
            await cb.message.answer("✅ <b>Hasil Pemeriksaan Auto-Heal:</b>\nSeluruh layanan (Xray, Dropbear, Multiplexer, Nginx) di semua server dalam keadaan <b>🟢 Sehat &amp; Aktif</b>!", parse_mode="HTML")
        else:
            rep = "🩺 <b>LAPORAN TINDAKAN AUTO-HEAL:</b>\n────────────────────────────\n" + "\n".join(events)
            await cb.message.answer(rep, parse_mode="HTML")
    elif act == "send_report":
        await cb.answer("📢 Mengirim laporan status server...")
        dash_txt = await asyncio.to_thread(build_admin_dashboard_text, ADMIN_ID, False)
        report_msg = f"📡 <b>LAPORAN STATUS SERVER (LIVE MONITOR)</b>\n{dash_txt}"
        await cb.message.answer(report_msg, parse_mode="HTML")
        grp_id = get_setting("group_chat_id", "").strip()
        topic_id = get_int_setting("group_topic_id", 0, 0) or get_int_setting("create_topic_id", 0, 0)
        if grp_id:
            kwargs = {"chat_id": int(grp_id), "text": report_msg, "parse_mode": "HTML"}
            if topic_id > 0:
                kwargs["message_thread_id"] = topic_id
            try:
                await bot.send_message(**kwargs)
            except Exception:
                pass



# --- FITUR V13: KELOLA PREFIX NAMA AKUN OTOMATIS (MISAL: sunek-) ---




# --- FITUR V14: AUTO-REPORT DATA USER LOGIN KE TOPIK GRUP ---
@router.message(Command("setlogin"))
async def cmd_set_login_topic(msg: Message):
    if msg.from_user.id != ADMIN_ID:
        return
    if msg.chat.id >= 0:
        await msg.reply("⚠️ Perintah <code>/setlogin</code> harus diketik di dalam <b>Grup / Topik Grup</b> tujuan!", parse_mode="HTML")
        return
    tid = msg.message_thread_id or 0
    set_setting("group_chat_id", str(msg.chat.id))
    set_setting("login_topic_id", str(tid))
    set_setting("login_report_enabled", "1")
    record_group_topic(msg)
    await msg.reply(
        f"✅ <b>Topik Laporan User Login Diaktifkan!</b>\n"
        f"• <b>Grup ID:</b> <code>{msg.chat.id}</code>\n"
        f"• <b>Topic Thread ID:</b> <code>{tid}</code>\n"
        f"• <b>Interval Kirim:</b> Setiap <code>{get_int_setting('login_report_interval_min', 60, 1)} Menit</code>",
        parse_mode="HTML"
    )

def format_protocol_login_messages(srv_row, login_data: dict, mask_user: bool = False, show_ip: bool = True) -> list:
    """
    Hanya menghasilkan pesan untuk protokol yang memiliki pengguna sedang online (> 0).
    Menampilkan pemakaian bandwidth aktual per user (contoh: ceroty 145MB 1IP | 5091).
    """
    h = html.escape
    ip_addr = PUBLIC_IP if srv_row["is_local"] == 1 else engine.get_srv_ipv4(srv_row)
    domain = srv_row["host"]
    isp = srv_row["isp"] if ("isp" in srv_row.keys() and srv_row["isp"]) else DEFAULT_ISP

    hdr_lines = []
    if show_ip:
        hdr_lines.append(f"IP     : {h(ip_addr)}")
    hdr_lines.append(f"DOMAIN : {h(domain)}")
    hdr_lines.append(f"ISP    : {h(isp)}")
    header_block = "<code>" + "\n".join(hdr_lines) + "</code>"

    messages = []

    # 1. Users Login SSH/Dropbear (Hanya jika ada yang sedang online)
    ssh_dict = login_data.get("ssh", {})
    if ssh_dict:
        user_lines = []
        for uname in sorted(ssh_dict.keys()):
            val = ssh_dict[uname]
            pids = val.get("pids", 1) if isinstance(val, dict) else int(val)
            used_s = val.get("used_str", "") if isinstance(val, dict) else ""
            disp_u = mask_str(uname) if mask_user else uname
            if used_s:
                user_lines.append(f"{h(disp_u)} {used_s} {pids} PID")
            else:
                user_lines.append(f"{h(disp_u)} {pids} PID")
        body_str = "\n".join(user_lines)
        msg_ssh = (
            f"{header_block}\n"
            "<blockquote><b>Users Login SSH/Dropbear</b></blockquote>\n"
            f"{body_str}\n\n"
            f"<b>Total : {len(ssh_dict)}</b>"
        )
        messages.append(msg_ssh)

    # 2. Users Login VMess, VLESS, Trojan (Hanya jika ada yang sedang online)
    proto_titles = [
        ("vmess", "Users Login VMess"),
        ("vless", "Users Login VLESS"),
        ("trojan", "Users Login Trojan"),
    ]
    for p_key, p_title in proto_titles:
        p_dict = login_data.get(p_key, {})
        if p_dict:
            user_lines = []
            for uname in sorted(p_dict.keys()):
                info = p_dict[uname]
                ip_c = info.get("ip_count", 1)
                port_num = info.get("port", 443)
                used_s = info.get("used_str", "1MB")
                disp_u = mask_str(uname) if mask_user else uname
                user_lines.append(f"{h(disp_u)} {used_s} {ip_c}IP | {port_num}")
            body_str = "\n".join(user_lines)
            msg_xray = (
                f"{header_block}\n"
                f"<blockquote><b>{p_title}</b></blockquote>\n"
                f"{body_str}\n\n"
                f"<b>Total : {len(p_dict)}</b>"
            )
            messages.append(msg_xray)

    return messages

async def dispatch_login_reports(also_send_to_chat_id: int = None) -> int:
    now = int(time.time())
    mask_u = get_setting("login_report_mask", "0") == "1"
    show_ip = get_setting("login_report_show_ip", "1") == "1"
    grp_id = get_setting("group_chat_id", "").strip()
    l_topic = (
        get_int_setting("login_topic_id", 0, 0)
        or get_int_setting("create_topic_id", 0, 0)
        or get_int_setting("group_topic_id", 0, 0)
    )

    with db_conn() as conn:
        srvs = conn.execute("SELECT * FROM servers ORDER BY id ASC").fetchall()
        acc_rows = conn.execute("SELECT username, protocol FROM accounts WHERE expired_at > ?", (now,)).fetchall()

    acc_proto_db = {r["username"]: r["protocol"] for r in acc_rows}

    total_messages_sent = 0
    for srv in srvs:
        raw_data = await asyncio.to_thread(engine.get_detailed_login_data, srv)
        fixed_data = {"ssh": raw_data.get("ssh", {}), "vmess": {}, "vless": {}, "trojan": {}}
        for pt in ("vmess", "vless", "trojan"):
            for uname, uinfo in raw_data.get(pt, {}).items():
                real_pt = acc_proto_db.get(uname, pt)
                if real_pt not in ("vmess", "vless", "trojan"):
                    real_pt = pt
                fixed_data[real_pt][uname] = uinfo

        msgs = format_protocol_login_messages(
            srv, fixed_data,
            mask_user=mask_u, show_ip=show_ip
        )
        for m_txt in msgs:
            if grp_id:
                kwargs = {"chat_id": int(grp_id), "text": m_txt, "parse_mode": "HTML"}
                if l_topic > 0:
                    kwargs["message_thread_id"] = l_topic
                try:
                    await bot.send_message(**kwargs)
                    total_messages_sent += 1
                except Exception:
                    pass
            if also_send_to_chat_id and (not grp_id or int(grp_id) != int(also_send_to_chat_id)):
                try:
                    await bot.send_message(chat_id=also_send_to_chat_id, text=m_txt, parse_mode="HTML")
                    total_messages_sent += 1
                except Exception:
                    pass
            await asyncio.sleep(0.3)

    return total_messages_sent

@router.callback_query(F.data == "adm_login_rep_menu")
async def cb_adm_login_rep_menu(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()

    rep_on = get_setting("login_report_enabled", "0") == "1"
    st_lbl = "🟢 ON (Aktif)" if rep_on else "🔴 OFF (Nonaktif)"
    intv_min = get_int_setting("login_report_interval_min", 60, 1)
    mask_on = get_setting("login_report_mask", "0") == "1"
    mask_lbl = "🔒 Sensor (su***01)" if mask_on else "👁 Tampil Utuh (bandung)"
    ip_on = get_setting("login_report_show_ip", "1") == "1"
    ip_lbl = "🟢 Tampil" if ip_on else "🔴 Sembunyikan"
    grp_id = get_setting("group_chat_id", "") or "Belum Diatur"
    l_topic = get_int_setting("login_topic_id", 0, 0) or get_int_setting("create_topic_id", 0, 0)

    with db_conn() as conn:
        topics = conn.execute("SELECT * FROM detected_topics ORDER BY updated_at DESC LIMIT 5").fetchall()

    txt = (
        "📊 <b>AUTO-REPORT DATA USER LOGIN KE TOPIK GRUP</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Status Auto-Report:</b> <b>{st_lbl}</b>\n"
        f"• <b>Interval Waktu:</b> Setiap <b>{intv_min} Menit</b>\n"
        f"• <b>Grup Tujuan:</b> <code>{html.escape(grp_id)}</code> (Topik: <code>#{l_topic}</code>)\n"
        f"• <b>Tampilan Username:</b> {mask_lbl}\n"
        f"• <b>Baris IP di Header:</b> {ip_lbl}\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "💡 <i>Fitur ini mengirimkan kartu daftar user yang sedang login (<b>SSH/Dropbear, VMess, VLESS, Trojan</b>) ke topik grup secara berkala persis seperti contoh gambar Anda.</i>\n"
        "📌 <i>Tips: Anda juga bisa mengetik <code>/setlogin</code> langsung di dalam topik grup tujuan.</i>"
    )
    kb = [
        [
            InlineKeyboardButton(
                text="🔴 Matikan Auto-Report (OFF)" if rep_on else "🟢 Aktifkan Auto-Report (ON)",
                callback_data="lrep_act:toggle"
            )
        ],
        [
            InlineKeyboardButton(text="⏱ 5m", callback_data="lrep_intv:5"),
            InlineKeyboardButton(text="⏱ 15m", callback_data="lrep_intv:15"),
            InlineKeyboardButton(text="⏱ 30m", callback_data="lrep_intv:30"),
            InlineKeyboardButton(text="⏱ 60m", callback_data="lrep_intv:60")
        ],
        [
            InlineKeyboardButton(text="✏️ Atur Waktu Manual (Menit)", callback_data="lrep_act:custom_intv")
        ],
        [
            InlineKeyboardButton(text=f"👤 Username: {'Sensor' if mask_on else 'Utuh'}", callback_data="lrep_act:toggle_mask"),
            InlineKeyboardButton(text=f"🌐 Baris IP: {'ON' if ip_on else 'OFF'}", callback_data="lrep_act:toggle_ip")
        ],
        [
            InlineKeyboardButton(text="⚡ Kirim Laporan Login Sekarang (Tes)", callback_data="lrep_act:send_now")
        ]
    ]
    for tp in topics:
        t_lbl = f"Topik #{tp['thread_id']}" if tp["thread_id"] > 0 else "General"
        kb.append([
            InlineKeyboardButton(
                text=f"📌 Set ke [{tp['chat_title'][:14]}] — {t_lbl}",
                callback_data=f"lrep_bind:{tp['chat_id']}:{tp['thread_id']}"
            )
        ])
    kb.append([InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")])
    await safe_edit_Basic(cb, txt, reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@router.callback_query(F.data.startswith("lrep_intv:"))
async def cb_lrep_intv(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    mins = int(cb.data.split(":")[1])
    set_setting("login_report_interval_min", str(mins))
    set_setting("login_report_enabled", "1")
    await cb.answer(f"⏱ Interval diatur setiap {mins} menit (Status: ON)!", show_alert=True)
    await cb_adm_login_rep_menu(cb, state)

@router.callback_query(F.data.startswith("lrep_bind:"))
async def cb_lrep_bind(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    _, cid, tid = cb.data.split(":")
    set_setting("group_chat_id", cid)
    set_setting("login_topic_id", tid)
    set_setting("login_report_enabled", "1")
    await cb.answer(f"✅ Topik Laporan Login diatur ke Grup {cid} (Topik #{tid})!", show_alert=True)
    await cb_adm_login_rep_menu(cb, state)

@router.callback_query(F.data.startswith("lrep_act:"))
async def cb_lrep_act(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    if act == "toggle":
        cur = get_setting("login_report_enabled", "0")
        new_v = "0" if cur == "1" else "1"
        set_setting("login_report_enabled", new_v)
        await cb.answer(f"📊 Auto-Report User Login: {'ON (Aktif)' if new_v == '1' else 'OFF (Nonaktif)'}", show_alert=True)
        await cb_adm_login_rep_menu(cb, state)
    elif act == "toggle_mask":
        cur = get_setting("login_report_mask", "0")
        set_setting("login_report_mask", "0" if cur == "1" else "1")
        await cb_adm_login_rep_menu(cb, state)
    elif act == "toggle_ip":
        cur = get_setting("login_report_show_ip", "1")
        set_setting("login_report_show_ip", "0" if cur == "1" else "1")
        await cb_adm_login_rep_menu(cb, state)
    elif act == "custom_intv":
        await state.set_state(FormState.admin_login_rep_interval)
        await safe_edit_Basic(
            cb,
            "⏱ <b>ATUR INTERVAL WAKTU AUTO-REPORT (MENIT)</b>\n"
            "────────────────────────────\n"
            "Silakan ketik angka <b>jumlah menit</b> jeda pengiriman laporan login ke topik grup (contoh: <code>30</code> atau <code>60</code>):",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_login_rep_menu")]])
        )
    elif act == "send_now":
        await cb.answer("⏳ Mengecek pengguna yang sedang online...")
        cnt = await dispatch_login_reports(also_send_to_chat_id=ADMIN_ID)
        if cnt == 0:
            await cb.answer("ℹ️ Saat ini tidak ada pengguna yang sedang online (tidak ada laporan yang dikirim).", show_alert=True)
        else:
            await cb.message.answer("✅ <b>Laporan pengguna online berhasil dikirim ke Topik Grup!</b>", parse_mode="HTML")

@router.message(FormState.admin_login_rep_interval)
async def msg_admin_login_rep_interval(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    m = re.search(r"\d+", (msg.text or "").strip())
    mins = max(1, int(m.group(0))) if m else 60
    await state.clear()
    set_setting("login_report_interval_min", str(mins))
    set_setting("login_report_enabled", "1")
    await msg.answer(
        f"✅ <b>Interval Auto-Report User Login berhasil diatur setiap {mins} Menit (Status: 🟢 ON)!</b>",
        parse_mode="HTML",
        reply_markup=admin_menu_kb()
    )

async def login_report_scheduler_worker():
    last_sent_ts = time.time()
    while True:
        await asyncio.sleep(15)
        try:
            if get_setting("login_report_enabled", "0") != "1":
                continue
            intv_min = get_int_setting("login_report_interval_min", 60, 1)
            now = time.time()
            if now - last_sent_ts >= (intv_min * 60):
                last_sent_ts = now
                await dispatch_login_reports(also_send_to_chat_id=None)
        except Exception:
            pass




async def auto_heal_monitor_worker():
    while True:
        await asyncio.sleep(60)
        try:
            if get_setting("auto_heal_enabled", "1") != "1":
                continue
            with db_conn() as conn:
                srvs = conn.execute("SELECT * FROM servers").fetchall()
            events = await asyncio.to_thread(engine.run_auto_heal_check, srvs)
            if events:
                now_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S WIB")
                log_activity("AUTO_HEAL", "; ".join([re.sub(r"<[^>]+>", "", e) for e in events]))
                if get_setting("notif_server_status", "1") == "1":
                    alert_txt = (
                        "🚨 <b>AUTO-HEAL &amp; STATUS SERVER ALERT</b> 🚨\n"
                        f"🕒 <b>Waktu:</b> <code>{now_str}</code>\n"
                        "────────────────────────────\n"
                        + "\n".join(events)
                    )
                    try:
                        await bot.send_message(ADMIN_ID, alert_txt, parse_mode="HTML")
                    except Exception:
                        pass
                    grp_id = get_setting("group_chat_id", "").strip()
                    topic_id = get_int_setting("group_topic_id", 0, 0)
                    if grp_id:
                        kwargs = {"chat_id": int(grp_id), "text": alert_txt, "parse_mode": "HTML"}
                        if topic_id > 0:
                            kwargs["message_thread_id"] = topic_id
                        try:
                            await bot.send_message(**kwargs)
                        except Exception:
                            pass
        except Exception:
            pass


# --- FITUR V13: KELOLA PREFIX NAMA AKUN OTOMATIS (MISAL: sunek-) ---
@router.callback_query(F.data == "adm_prefix_menu")
async def cb_adm_prefix_menu(cb: CallbackQuery, state: FSMContext = None):
    if cb.from_user.id != ADMIN_ID:
        return
    if state:
        await state.clear()
    pfx_on = get_setting("prefix_enabled", "1") == "1"
    pfx_val = get_setting("account_prefix", "sunek").strip().strip("-") or "sunek"
    st_lbl = "🟢 ON (Aktif)" if pfx_on else "🔴 OFF (Nonaktif)"
    cur_dom = get_current_main_domain()

    ex_trial = f"{pfx_val}-trial80994" if pfx_on else "trial80994"
    ex_reg = f"{pfx_val}-member01" if pfx_on else "member01"

    txt = (
        "🏷️ <b>PENGATURAN PREFIX NAMA AKUN OTOMATIS</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        f"• <b>Status Prefix:</b> <b>{st_lbl}</b>\n"
        f"• <b>Nama Prefix:</b> <code>{html.escape(pfx_val)}-</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "<b>Contoh Hasil Pembuatan Akun Saat Ini:</b>\n"
        f"• <b>SSH Trial:</b>\n  <code>{html.escape(cur_dom)}:443@{html.escape(ex_trial)}:123a9</code>\n"
        f"• <b>Akun Reguler (SSH/Xray):</b>\n  <code>{html.escape(ex_reg)}</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "<i>Gunakan tombol di bawah untuk mengaktifkan/mematikan (ON/OFF) atau mengganti teks penanda prefix:</i>"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(
                text="🔴 Matikan Prefix (OFF)" if pfx_on else "🟢 Aktifkan Prefix (ON)",
                callback_data="pfx_act:toggle"
            )
        ],
        [
            InlineKeyboardButton(text=f"✏️ Ubah Nama Prefix ({pfx_val})", callback_data="pfx_act:edit")
        ],
        [
            InlineKeyboardButton(text="⬅️ Kembali ke Panel Admin", callback_data="admin_home")
        ]
    ])
    await safe_edit_Basic(cb, txt, reply_markup=kb)

@router.callback_query(F.data.startswith("pfx_act:"))
async def cb_pfx_act(cb: CallbackQuery, state: FSMContext):
    if cb.from_user.id != ADMIN_ID:
        return
    act = cb.data.split(":")[1]
    if act == "toggle":
        cur = get_setting("prefix_enabled", "1")
        new_v = "0" if cur == "1" else "1"
        set_setting("prefix_enabled", new_v)
        await cb.answer(f"🏷️ Prefix Akun: {'ON (Aktif)' if new_v == '1' else 'OFF (Nonaktif)'}", show_alert=True)
        await cb_adm_prefix_menu(cb, state)
    elif act == "edit":
        await state.set_state(FormState.admin_set_prefix)
        cur_p = get_setting("account_prefix", "sunek")
        await safe_edit_Basic(
            cb,
            "✏️ <b>UBAH NAMA PREFIX AKUN</b>\n"
            "────────────────────────────\n"
            f"• Prefix saat ini: <code>{html.escape(cur_p)}-</code>\n\n"
            "Silakan ketik kata/nama prefix baru yang diinginkan tanpa spasi (contoh: <code>sunek</code>):",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="⬅️ Batal", callback_data="adm_prefix_menu")]])
        )

@router.message(FormState.admin_set_prefix)
async def msg_admin_set_prefix(msg: Message, state: FSMContext):
    if msg.from_user.id != ADMIN_ID:
        return
    raw_p = re.sub(r"[^a-zA-Z0-9]", "", (msg.text or "").strip())
    await state.clear()
    if not raw_p:
        await msg.answer("⚠️ Nama prefix tidak valid (gunakan huruf/angka).", reply_markup=admin_menu_kb())
        return
    set_setting("account_prefix", raw_p)
    set_setting("prefix_enabled", "1")
    await msg.answer(
        f"✅ <b>Nama Prefix berhasil disimpan menjadi:</b> <code>{html.escape(raw_p)}-</code> (Status: <b>🟢 ON</b>)",
        parse_mode="HTML",
        reply_markup=admin_menu_kb()
    )

@router.message(F.chat.id < 0)
async def msg_group_listener(msg: Message):
    record_group_topic(msg)

async def scanner_multi_login_worker():
    while True:
        await asyncio.sleep(10)
        try:
            active_map = engine.scan_active_sessions()
            now = int(time.time())
            lock_en = get_setting("lock_enabled", "1") == "1"
            base_dur = get_int_setting("lock_duration_min", 5, 1)
            max_strikes = get_int_setting("lock_strikes", 1, 1)
            tiered = get_setting("lock_tiered", "1") == "1"
            notifications = []

            with db_conn() as conn:
                accs = conn.execute("SELECT * FROM accounts WHERE expired_at > ?", (now,)).fetchall()
                for acc in accs:
                    uname = acc["username"]
                    if uname in active_map:
                        ips = sorted(list(active_map[uname]["ips"]))
                        sess_cnt = active_map[uname]["sessions"]
                        conn.execute("UPDATE accounts SET last_ips=?, active_sessions=? WHERE id=?", (",".join(ips), sess_cnt, acc["id"]))
                        if lock_en and acc["locked_until"] <= now and len(ips) > acc["ip_limit"]:
                            new_strike = acc["strike_count"] + 1
                            if new_strike >= max_strikes:
                                v_level = acc["violation_level"] + 1
                                lock_mins = base_dur * (v_level if tiered else 1)
                                until_ts = now + (lock_mins * 60)
                                jam_wib = datetime.fromtimestamp(until_ts).strftime("%H:%M WIB")
                                if acc["protocol"] == "ssh": engine.lock_ssh_user(uname)
                                else: engine.remove_xray_user(acc["protocol"], uname)
                                conn.execute("UPDATE accounts SET locked_until=?, strike_count=0, violation_level=?, active_sessions=0 WHERE id=?", (until_ts, v_level, acc["id"]))
                                conn.execute("INSERT INTO activity_logs (ts, event, detail) VALUES (?, ?, ?)", (now, "AUTO_LOCK", f"{uname} dikunci {lock_mins}m ({len(ips)} IP)"))
                                notifications.append({
                                    "user_id": acc["user_id"], "uname": uname, "proto": acc["protocol"].upper(),
                                    "ip_cnt": len(ips), "ip_limit": acc["ip_limit"], "ips_str": ", ".join(ips),
                                    "lock_mins": lock_mins, "jam_wib": jam_wib
                                })
                            else:
                                conn.execute("UPDATE accounts SET strike_count=? WHERE id=?", (new_strike, acc["id"]))
                        else:
                            conn.execute("UPDATE accounts SET strike_count=0 WHERE id=?", (acc["id"],))
                    else:
                        conn.execute("UPDATE accounts SET active_sessions=0 WHERE id=?", (acc["id"],))
                conn.commit()

            grp_id = get_setting("group_chat_id", "").strip()
            topic_id = get_int_setting("group_topic_id", 0, 0)
            for n in notifications:
                try:
                    await bot.send_message(n["user_id"], f"Akun {n['uname']} dikunci {n['lock_mins']} menit karena login dari {n['ip_cnt']} IP. Otomatis aktif kembali pukul {n['jam_wib']}.")
                except Exception:
                    pass
                if grp_id:
                    notif_txt = (
                        "PELANGGARAN MULTI-LOGIN TERDETEKSI\n"
                        f"Username : {n['uname']} ({n['proto']})\nJumlah IP : {n['ip_cnt']} IP (Limit {n['ip_limit']} IP)\n"
                        f"Daftar IP : {n['ips_str']}\nDurasi Lock : {n['lock_mins']} Menit\nAktif Kembali : {n['jam_wib']}"
                    )
                    kwargs = {"chat_id": int(grp_id), "text": notif_txt}
                    if topic_id > 0: kwargs["message_thread_id"] = topic_id
                    try: await bot.send_message(**kwargs)
                    except Exception: pass
        except Exception:
            pass


PROTO_DISPLAY_MAP = {
    "ssh": "SSH",
    "vmess": "VMess",
    "vless": "VLESS",
    "trojan": "Trojan",
}

def build_exact_multilogin_msg(srv_ip: str, srv_host: str, srv_isp: str, proto: str, uname: str, ip_events: list, lock_hms: str, open_hms: str) -> str:
    h = html.escape
    proto_lbl = PROTO_DISPLAY_MAP.get(proto.lower(), proto.upper())

    ip_lines = []
    for ev in ip_events:
        t_str = h(str(ev.get("time", lock_hms)))
        raw_ip = str(ev.get("ip", "")).split(" ")[0]
        if ":" in raw_ip and raw_ip.count(":") == 1:
            clean_ip = raw_ip.split(":")[0]
        else:
            clean_ip = raw_ip
        clean_ip_esc = h(clean_ip)
        ip_lines.append(f'{t_str} <a href="http://{clean_ip_esc}">{clean_ip_esc}</a>')

    ip_block_str = "\n".join(ip_lines)

    return (
        f"<code>IP     : {h(srv_ip)}\n"
        f"DOMAIN : {h(srv_host)}\n"
        f"ISP    : {h(srv_isp)}</code>\n"
        f"<blockquote><b>Multi Login {h(proto_lbl)}</b></blockquote>\n"
        f"✓ {h(uname)}\n"
        f"{ip_block_str}\n"
        f"<blockquote>Lock - {h(lock_hms)}\n"
        f"Open - {h(open_hms)}</blockquote>"
    )

async def unlock_and_expiry_worker():
    last_guard_sync = 0
    while True:
        await asyncio.sleep(5)
        try:
            now = int(time.time())
            global_ip_lim = get_int_setting("default_ip_limit", 2, 0)
            global_days_lim = get_int_setting("default_days", 1, 0)

            with db_conn() as conn:
                srvs = conn.execute("SELECT * FROM servers").fetchall()
                srv_map = {s["id"]: s for s in srvs}

                # 1. Hapus akun yang sudah Expired (Jika Masa Aktif Reguler = 0 / Unlimited, akun reguler tidak pernah expired)
                expired_rows = conn.execute(
                    "SELECT * FROM accounts WHERE expired_at > 0 AND expired_at < 4000000000 AND expired_at <= ?",
                    (now,)
                ).fetchall()
                for r in expired_rows:
                    if r["is_trial"] == 0 and global_days_lim == 0:
                        conn.execute("UPDATE accounts SET expired_at=4102444800 WHERE id=?", (r["id"],))
                        continue
                    target_srv = srv_map.get(r["server_id"])
                    await asyncio.to_thread(engine.remove_account_from_server, target_srv, r["protocol"], r["username"])
                    conn.execute("DELETE FROM accounts WHERE id=?", (r["id"],))
                if expired_rows:
                    conn.commit()

                # 2. AUTO-UNLOCK + AUTO-SINKRONISASI PASSWORD SSH / UUID XRAY OTOMATIS
                #    Jika global_ip_lim == 0 (Unlimited IP), buka juga seluruh akun yang sedang terkunci!
                if global_ip_lim == 0:
                    unlock_rows = conn.execute(
                        "SELECT * FROM accounts WHERE locked_until > 0 AND expired_at > ?",
                        (now,)
                    ).fetchall()
                else:
                    unlock_rows = conn.execute(
                        "SELECT * FROM accounts WHERE locked_until > 0 AND locked_until <= ? AND expired_at > ?",
                        (now, now)
                    ).fetchall()

                for r in unlock_rows:
                    target_srv = srv_map.get(r["server_id"])
                    await asyncio.to_thread(
                        engine.set_remote_or_local_lock,
                        target_srv, r["protocol"], r["username"], r["secret"], False
                    )
                    conn.execute(
                        "UPDATE accounts SET locked_until=0, strike_count=0, active_sessions=0, last_ips='' WHERE id=?",
                        (r["id"],)
                    )
                    conn.commit()
                    log_activity("AUTO_UNLOCK", f"{r['username']} ({r['protocol'].upper()}) otomatis dibuka & disinkronkan")
                    try:
                        await bot.send_message(
                            r["user_id"],
                            f"🔓 Akun <code>{html.escape(r['username'])}</code> ({r['protocol'].upper()}) telah aktif kembali!",
                            parse_mode="HTML"
                        )
                    except Exception:
                        pass

                # 2b. AUTO-SYNC GUARD setiap 45 detik
                if now - last_guard_sync >= 45:
                    last_guard_sync = now
                    unlocked_ssh = conn.execute(
                        "SELECT * FROM accounts WHERE protocol='ssh' AND locked_until=0 AND expired_at > ?",
                        (now,)
                    ).fetchall()
                    for u_acc in unlocked_ssh:
                        t_srv = srv_map.get(u_acc["server_id"])
                        await asyncio.to_thread(
                            engine.set_remote_or_local_lock,
                            t_srv, "ssh", u_acc["username"], u_acc["secret"], False
                        )

            # 3. Cek Multi-Login (HANYA jika lock_enabled == 1 DAN global_ip_lim > 0)
            if get_setting("lock_enabled", "1") != "1" or global_ip_lim == 0:
                continue

            sessions_by_srv = {}
            detail_by_srv = {}
            for sid, s_row in srv_map.items():
                if s_row["is_local"] == 1:
                    sessions_by_srv[sid] = await asyncio.to_thread(engine.get_active_sessions)
                    detail_by_srv[sid] = await asyncio.to_thread(engine.get_detailed_login_data_local)
                else:
                    sessions_by_srv[sid] = await asyncio.to_thread(engine.get_remote_active_sessions, s_row)
                    detail_by_srv[sid] = await asyncio.to_thread(engine.get_detailed_login_data, s_row)

            lock_base_min = get_int_setting("lock_duration_min", 5, 1)
            max_strikes = get_int_setting("lock_strikes", 1, 1)
            tiered = get_setting("lock_tiered", "1") == "1"

            notifs_to_send = []
            with db_conn() as conn:
                active_accs = conn.execute(
                    "SELECT * FROM accounts WHERE expired_at > ? AND locked_until <= ?",
                    (now, now)
                ).fetchall()

                for acc in active_accs:
                    sid = acc["server_id"] if acc["server_id"] in sessions_by_srv else 1
                    sess_data = sessions_by_srv.get(sid, {"ssh": {}, "xray": {}})
                    det_data = detail_by_srv.get(sid, {})
                    ip_times_map = det_data.get("ip_times", {})
                    uname = acc["username"]
                    proto = acc["protocol"]
                    ip_map = sess_data["ssh"] if proto == "ssh" else sess_data["xray"]
                    ips = ip_map.get(uname, [])
                    ip_count = len(ips)
                    ip_str = ", ".join(ips)

                    conn.execute(
                        "UPDATE accounts SET active_sessions=?, last_ips=? WHERE id=?",
                        (ip_count, ip_str, acc["id"])
                    )

                    eff_ip_limit = int(acc["ip_limit"]) if acc["ip_limit"] is not None else global_ip_lim
                    if eff_ip_limit > 0 and ip_count > eff_ip_limit:
                        strikes = (acc["strike_count"] or 0) + 1
                        if strikes >= max_strikes:
                            v_level = (acc["violation_level"] or 0) + 1
                            dur_min = lock_base_min * (v_level if tiered else 1)
                            locked_until = now + (dur_min * 60)
                            target_srv = srv_map.get(sid)

                            await asyncio.to_thread(
                                engine.set_remote_or_local_lock,
                                target_srv, proto, uname, acc["secret"], True
                            )
                            conn.execute(
                                "UPDATE accounts SET locked_until=?, strike_count=0, violation_level=? WHERE id=?",
                                (locked_until, v_level, acc["id"])
                            )
                            conn.commit()

                            local_pub_ip = ENV_CONFIG.get("PUBLIC_IP", "127.0.0.1")
                            srv_ip = local_pub_ip if (not target_srv or target_srv["is_local"] == 1) else engine.get_srv_ipv4(target_srv)
                            srv_host = target_srv["host"] if target_srv else DEFAULT_DOMAIN
                            srv_isp = (target_srv["isp"] if (target_srv and "isp" in target_srv.keys() and target_srv["isp"]) else DEFAULT_ISP)

                            now_hms = datetime.fromtimestamp(now).strftime("%H:%M:%S")
                            open_hms = datetime.fromtimestamp(locked_until).strftime("%H:%M:%S")
                            u_times = ip_times_map.get(uname, {})

                            ip_events_list = []
                            for raw_ip in ips:
                                clean_ip = raw_ip.split(" ")[0]
                                if ":" in clean_ip and clean_ip.count(":") == 1:
                                    clean_ip = clean_ip.split(":")[0]
                                t_hms = u_times.get(clean_ip, now_hms)
                                ip_events_list.append({"time": t_hms, "ip": clean_ip})

                            notifs_to_send.append({
                                "user_id": acc["user_id"],
                                "uname": uname,
                                "proto": proto,
                                "srv_ip": srv_ip,
                                "srv_host": srv_host,
                                "srv_isp": srv_isp,
                                "ip_count": ip_count,
                                "ip_limit": eff_ip_limit,
                                "ip_events": ip_events_list,
                                "dur_min": dur_min,
                                "lock_hms": now_hms,
                                "open_hms": open_hms
                            })
                        else:
                            conn.execute("UPDATE accounts SET strike_count=? WHERE id=?", (strikes, acc["id"]))
                    else:
                        if (acc["strike_count"] or 0) > 0:
                            conn.execute("UPDATE accounts SET strike_count=0 WHERE id=?", (acc["id"],))
                conn.commit()

            for n in notifs_to_send:
                log_activity("AUTO_LOCK", f"{n['uname']} ({n['proto'].upper()}) dikunci {n['dur_min']}m ({n['ip_count']}/{n['ip_limit']} IP)")

                notif_html = build_exact_multilogin_msg(
                    srv_ip=n["srv_ip"],
                    srv_host=n["srv_host"],
                    srv_isp=n["srv_isp"],
                    proto=n["proto"],
                    uname=n["uname"],
                    ip_events=n["ip_events"],
                    lock_hms=n["lock_hms"],
                    open_hms=n["open_hms"]
                )

                try:
                    await bot.send_message(
                        chat_id=n["user_id"],
                        text=notif_html,
                        parse_mode="HTML",
                        disable_web_page_preview=True
                    )
                except Exception:
                    pass

                grp_id = get_setting("group_chat_id", "").strip()
                l_topic = get_int_setting("group_topic_id", 0, 0) or get_int_setting("create_topic_id", 0, 0)
                if grp_id:
                    kwargs = {
                        "chat_id": int(grp_id),
                        "text": notif_html,
                        "parse_mode": "HTML",
                        "disable_web_page_preview": True
                    }
                    if l_topic > 0:
                        kwargs["message_thread_id"] = l_topic
                    try:
                        await bot.send_message(**kwargs)
                    except Exception:
                        # Fallback jika thread_id berubah/dihapus, kirim ke grup utama agar tidak pernah gagal
                        try:
                            kwargs.pop("message_thread_id", None)
                            await bot.send_message(**kwargs)
                        except Exception:
                            pass
        except Exception:
            pass

async def main():
    init_db()
    asyncio.create_task(scanner_multi_login_worker())
    asyncio.create_task(unlock_and_expiry_worker())
    asyncio.create_task(login_report_scheduler_worker())
    asyncio.create_task(auto_heal_monitor_worker())
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF_EMBED_FILE
chmod +x /etc/vpn-bot/bot.py 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/send_backup.py
#!/usr/bin/env python3
import os
import subprocess
import sys
import time

ENV_CONFIG = {}
with open("/etc/vpn-bot/config.env", "r") as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            ENV_CONFIG[k.strip()] = v.strip().strip('"')

BOT_TOKEN = ENV_CONFIG.get("BOT_TOKEN", "")
ADMIN_ID = ENV_CONFIG.get("ADMIN_ID", "")
CURRENT_DOMAIN = ENV_CONFIG.get("DOMAIN", "")
if not BOT_TOKEN or not ADMIN_ID:
    print("config.env tidak lengkap (BOT_TOKEN/ADMIN_ID hilang) — backup dibatalkan.", file=sys.stderr)
    sys.exit(1)
FULL_SCRIPT_PATH = "/root/setup-vpn-full.sh"

def read_clean(path):
    if not os.path.exists(path):
        return ""
    with open(path, "r", errors="ignore") as f:
        c = f.read()
    if path == "/etc/nginx/nginx.conf" and CURRENT_DOMAIN:
        c = c.replace(CURRENT_DOMAIN, "__DOMAIN__")
    return c

def build_portable_installer():
    files = {
        "/etc/issue.net": read_clean("/etc/issue.net"),
        "/etc/vpn-bot/ws-bridge.py": read_clean("/etc/vpn-bot/ws-bridge.py"),
        "/etc/vpn-bot/proto-daemons.py": read_clean("/etc/vpn-bot/proto-daemons.py"),
        "/etc/vpn-bot/vpn_engine.py": read_clean("/etc/vpn-bot/vpn_engine.py"),
        "/etc/vpn-bot/bot.py": read_clean("/etc/vpn-bot/bot.py"),
        "/etc/vpn-bot/send_backup.py": read_clean("/etc/vpn-bot/send_backup.py"),
        "/etc/vpn-bot/remote_installer.sh": read_clean("/etc/vpn-bot/remote_installer.sh"),
        "/etc/nginx/nginx.conf": read_clean("/etc/nginx/nginx.conf"),
    }
    with open(FULL_SCRIPT_PATH, "w") as out:
        out.write("""#!/usr/bin/env bash
# ==============================================================================
#  PORTABLE ONE-CLICK VPN & TELEGRAM BOT INSTALLER (FRESH VPS READY)
#  Support: Ubuntu 18.04 - 24.04 & Debian 10 - 13 (Semua Spesifikasi RAM/CPU)
#  Tanpa Hardcode Bot Token, Admin ID, atau Domain (Input Saat Install)
# ==============================================================================
set -e
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /var/log/xray /etc/xray/certs /etc/dropbear /var/www/html

clear
echo "========================================================================"
echo "      INSTALASI PORTABLE SERVER VPN & BOT TELEGRAM (SEKALI PASANG)      "
echo "========================================================================"
read -rp "Masukkan Bot Token Telegram : " BOT_TOKEN
read -rp "Masukkan Admin ID Telegram  : " ADMIN_ID
read -rp "Masukkan Domain VPS (A Rec) : " DOMAIN

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" || -z "$DOMAIN" ]]; then
    echo "Error: Bot Token, Admin ID, dan Domain wajib diisi!"
    exit 1
fi

# 1. Buka Paksa Kunci APT/DPKG (Mengatasi lock-frontend PID 1410 di VPS Baru)
echo "[1/6] Membebaskan kunci APT/DPKG & mengoptimasi Swap RAM..."
systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service apt-daily.service apt-daily-upgrade.service >/dev/null 2>&1 || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service >/dev/null 2>&1 || true
killall -9 apt apt-get dpkg unattended-upgr >/dev/null 2>&1 || true
sleep 1
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
dpkg --configure -a --force-confdef --force-confold >/dev/null 2>&1 || true

systemctl stop systemd-resolved >/dev/null 2>&1 || true
systemctl disable systemd-resolved >/dev/null 2>&1 || true
rm -f /etc/resolv.conf
echo -e "nameserver 1.1.1.1\\nnameserver 8.8.8.8" > /etc/resolv.conf
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

ARCH_RAW=$(uname -m)
if [[ "$ARCH_RAW" == "x86_64" ]]; then ARCH="64"; else ARCH="arm64-v8a"; fi

# Unduh Xray dengan fallback multi-mirror (GitHub kadang terblokir di VPS ID)
fetch_xray() {
    local arch="$1" url tmp="/tmp/xray.zip"
    url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    rm -f "$tmp"
    if wget -q --timeout=60 -O "$tmp" "$url"; then return 0; fi
    if wget -q --timeout=90 -O "$tmp" "https://ghproxy.com/$url"; then return 0; fi
    if [[ -f /root/xray-linux-${arch}.zip ]]; then
        cp -f "/root/xray-linux-${arch}.zip" "$tmp"; return 0
    fi
    return 1
}

VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "kvm")

# Buat Auto-Swap 1 GB di awal agar VPS RAM 512MB tidak pernah stuck/freeze
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [[ "$VIRT_TYPE" != "openvz" && "$VIRT_TYPE" != "lxc" ]]; then
    if [[ "$TOTAL_RAM" -lt 2000 ]] && [[ $(swapon --show | wc -l) -eq 0 ]]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 >/dev/null 2>&1
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile >/dev/null 2>&1 || true
        grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    cat << 'EOS' > /etc/sysctl.d/99-vpn-hardening.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
EOS
    sysctl --system >/dev/null 2>&1 || true
fi

# 2. Instalasi Paket Dasar (Support Ubuntu <= 24.04 & Debian <= 13)
echo "[2/6] Menginstal paket sistem & dependensi..."
apt-get update -y -o DPkg::Lock::Timeout=120
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o DPkg::Lock::Timeout=120 \\
    curl wget jq git unzip tar socat cron net-tools lsof psmisc \\
    iptables iptables-persistent netfilter-persistent fail2ban certbot \\
    nginx openssh-server dropbear squid openvpn easy-rsa \\
    build-essential zlib1g-dev bzip2 python3 python3-pip python3-venv \\
    sqlite3 bc vnstat wondershaper logrotate qrencode openssl >/dev/null 2>&1 || true
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \\
    libnginx-mod-stream >/dev/null 2>&1 || \\
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \\
    nginx-full >/dev/null 2>&1 || true
apt-get install -y -o DPkg::Lock::Timeout=60 libcrypt-dev python3-full >/dev/null 2>&1 || true

PUBLIC_IP=$(curl -s4 --max-time 5 ifconfig.me || curl -s4 --max-time 5 api.ipify.org || echo "127.0.0.1")
GEO_JSON=$(curl -s --max-time 5 https://ipinfo.io/json || echo "{}")
VPS_CITY=$(echo "$GEO_JSON" | jq -r '.city // "Singapore"')
VPS_ISP=$(echo "$GEO_JSON" | jq -r '.org // "Cloud ISP"' | sed 's/^AS[0-9]* //')

cat << EOC > /etc/vpn-bot/config.env
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
DOMAIN="$DOMAIN"
PUBLIC_IP="$PUBLIC_IP"
VPS_CITY="$VPS_CITY"
VPS_ISP="$VPS_ISP"
ARCH="$ARCH"
VIRT_TYPE="$VIRT_TYPE"
EOC

if [[ ! -f /etc/vpn-bot/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /etc/vpn-bot/id_ed25519 -C "vpn-bot-master" >/dev/null 2>&1
    chmod 600 /etc/vpn-bot/id_ed25519 && chmod 644 /etc/vpn-bot/id_ed25519.pub
fi
""")
        for fp, content in files.items():
            out.write(f"\ncat << 'EOF_EMBED_FILE' > {fp}\n{content}\nEOF_EMBED_FILE\nchmod +x {fp} 2>/dev/null || true\n")

        out.write("""
# 3. Konfigurasi SSH, Dropbear 2019.78 & Unit Service Lengkap
echo "[3/6] Mengompilasi Dropbear v2019.78 & menyiapkan service..."
grep -q "^/bin/false$" /etc/shells || echo "/bin/false" >> /etc/shells
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^Banner /d' /etc/ssh/sshd_config
echo -e "Port 22\\nPort 444\\nBanner /etc/issue.net\\nPermitRootLogin yes\\nPasswordAuthentication yes\\nPubkeyAuthentication yes" >> /etc/ssh/sshd_config
systemctl disable --now ssh.socket 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

cd /tmp && rm -rf dropbear-2019.78*
if wget -q --timeout=15 "https://matt.ucc.asn.au/dropbear/releases/dropbear-2019.78.tar.bz2" -O dropbear-2019.78.tar.bz2 || \\
   wget -q --timeout=15 "https://dropbear.nl/mirror/releases/dropbear-2019.78.tar.bz2" -O dropbear-2019.78.tar.bz2; then
    tar -xjf dropbear-2019.78.tar.bz2 && cd dropbear-2019.78
    if ./configure CFLAGS="-O2 -fcommon -Wno-error -Wno-unused-result" --prefix=/usr --sysconfdir=/etc/dropbear >/dev/null 2>&1; then
        if make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j2 >/dev/null 2>&1; then
            systemctl stop dropbear >/dev/null 2>&1 || true
            killall -9 dropbear >/dev/null 2>&1 || true
            cp -f dropbear /usr/sbin/dropbear && cp -f dbclient dropbearkey dropbearconvert /usr/bin/
            chmod +x /usr/sbin/dropbear /usr/bin/dropbearkey
            apt-mark hold dropbear dropbear-bin >/dev/null 2>&1 || true
        fi
    fi
fi
cd /root && rm -rf /tmp/dropbear-2019.78*
[[ -f /etc/dropbear/dropbear_rsa_host_key ]] || /usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
[[ -f /etc/dropbear/dropbear_ecdsa_host_key ]] || /usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
touch /var/log/dropbear.log /var/log/vpn-ws-map.log && chmod 666 /var/log/dropbear.log /var/log/vpn-ws-map.log

systemctl stop dropbear >/dev/null 2>&1 || true
rm -f /etc/init.d/dropbear
cat << 'EODBSVC' > /etc/systemd/system/dropbear.service
[Unit]
Description=Dropbear SSH Server v2019.78 (Port 90)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -EF -p 90 -W 65536 -b /etc/issue.net -r /etc/dropbear/dropbear_rsa_host_key -r /etc/dropbear/dropbear_ecdsa_host_key
StandardOutput=append:/var/log/dropbear.log
StandardError=append:/var/log/dropbear.log
KillMode=process
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EODBSVC

# 4. Instalasi Xray-Core & Sertifikat SSL
echo "[4/6] Memasang Xray-Core & Sertifikat SSL..."
if ! fetch_xray "$ARCH"; then
    echo "GAGAL: Tidak bisa mengunduh Xray dari semua sumber."
    echo "Solusi: upload manual binary ke /root/xray-linux-${ARCH}.zip lalu jalankan ulang."
    exit 1
fi
unzip -qo /tmp/xray.zip -d /usr/local/bin/ && chmod +x /usr/local/bin/xray && rm -f /tmp/xray.zip
touch /var/log/xray/access.log /var/log/xray/error.log && chmod 666 /var/log/xray/*.log

cat << 'EOXRAY' > /etc/xray/config.json
{
  "log": { "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info" },
  "inbounds": [
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 10001, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } } },
    { "tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10002, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vmess" } } },
    { "tag": "vmess-up", "listen": "127.0.0.1", "port": 10003, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvmess" } } },
    { "tag": "vless-ws", "listen": "127.0.0.1", "port": 10004, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } } },
    { "tag": "vless-grpc", "listen": "127.0.0.1", "port": 10005, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless" } } },
    { "tag": "vless-up", "listen": "127.0.0.1", "port": 10006, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvless" } } },
    { "tag": "trojan-ws", "listen": "127.0.0.1", "port": 10007, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" } } },
    { "tag": "trojan-grpc", "listen": "127.0.0.1", "port": 10008, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "trojan" } } },
    { "tag": "trojan-up", "listen": "127.0.0.1", "port": 10009, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/uptrojan" } } },
    { "tag": "ss-ws", "listen": "127.0.0.1", "port": 10010, "protocol": "shadowsocks", "settings": { "method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/ss-ws" } } },
    { "tag": "ss-grpc", "listen": "127.0.0.1", "port": 10011, "protocol": "shadowsocks", "settings": { "method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "ss-grpc" } } }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": {} },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ],
  "routing": { "domainStrategy": "AsIs", "rules": [ { "type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked" } ] }
}
EOXRAY

cat << 'EOSVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
Environment=TZ=UTC
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=always
RestartSec=1
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOSVC

systemctl stop nginx >/dev/null 2>&1 || true
if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}" >/dev/null 2>&1; then
    cp -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/xray/certs/fullchain.pem
    cp -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/xray/certs/privkey.pem
else
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/xray/certs/privkey.pem -out /etc/xray/certs/fullchain.pem -subj "/CN=${DOMAIN}" >/dev/null 2>&1
fi
chmod 644 /etc/xray/certs/fullchain.pem /etc/xray/certs/privkey.pem

# 5. Konfigurasi Nginx Stream & Systemd Services
echo "[5/6] Mengonfigurasi Nginx Stream & Systemd Services..."
mkdir -p /etc/nginx/modules-enabled
if ! ls /etc/nginx/modules-enabled/*stream*.conf >/dev/null 2>&1; then
    if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]]; then
        echo "load_module /usr/lib/nginx/modules/ngx_stream_module.so;" > /etc/nginx/modules-enabled/50-mod-stream.conf
    fi
fi
rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/default
sed -i "s/__DOMAIN__/${DOMAIN}/g" /etc/nginx/nginx.conf
if [[ ! -f /proc/net/if_inet6 ]] || [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null) == "1" ]]; then
    sed -i '/listen \\[\\:\\:\\]:/d' /etc/nginx/nginx.conf
fi

cat << 'EOWSSVC' > /etc/systemd/system/vpn-ws-bridge.service
[Unit]
Description=SSH WebSocket & Xray Real-IP Bridge
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/ws-bridge.py
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOWSSVC

cat << 'EOPDSVC' > /etc/systemd/system/vpn-proto-daemons.service
[Unit]
Description=VPN Auxiliary Protocols Daemon
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/proto-daemons.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOPDSVC

cat << 'EOBOTSVC' > /etc/systemd/system/vpn-telegram-bot.service
[Unit]
Description=Telegram VPN Community Bot
After=network.target xray.service dropbear.service

[Service]
Type=simple
WorkingDirectory=/etc/vpn-bot
ExecStart=/etc/vpn-bot/venv/bin/python /etc/vpn-bot/bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOBOTSVC

# 6. Buat Virtualenv Python & Aktifkan Semua Layanan
echo "[6/6] Menyiapkan Python Virtualenv & menyalakan seluruh layanan..."
python3 -m venv /etc/vpn-bot/venv
/etc/vpn-bot/venv/bin/pip install -U pip aiogram paramiko aiohttp >/dev/null

IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[[ -z "$IFACE" ]] && IFACE="eth0"
systemctl enable --now vnstat >/dev/null 2>&1 || true
vnstat --add -i "$IFACE" >/dev/null 2>&1 || true

# ===== SlowDNS (dnstt) + UDP-Custom auto-install =====
echo "[6/6b] Memasang SlowDNS (dnstt) & UDP-Custom..."
ARCH_X=$(uname -m)
case "$ARCH_X" in x86_64) XARCH="amd64";; aarch64|arm64) XARCH="arm64";; *) XARCH="amd64";; esac
mkdir -p /etc/slowdns /etc/udp /etc/iptables
# --- dnstt-server ---
if [[ ! -x /usr/local/bin/dnstt-server ]]; then
    wget -qO /usr/local/bin/dnstt-server \
        "https://github.com/net2share/dnstt/releases/download/latest/dnstt-server-linux-${XARCH}" \
        2>/dev/null || true
    chmod +x /usr/local/bin/dnstt-server 2>/dev/null || true
fi
# --- udp-custom ---
if [[ ! -x /usr/local/bin/udp-custom ]]; then
    UC_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
    if [[ "$XARCH" == "arm64" ]]; then
        UC_URL="https://raw.githubusercontent.com/fisabiliyusri/Mantap/main/udp-custom/udp-custom-linux-arm"
    fi
    wget -qO /usr/local/bin/udp-custom "$UC_URL" 2>/dev/null || true
    chmod +x /usr/local/bin/udp-custom 2>/dev/null || true
fi
# --- systemd-resolved: matikan agar :53 bebas ---
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
# --- generate key dnstt (sekali saja) ---
if [[ ! -f /etc/slowdns/server.pub && -x /usr/local/bin/dnstt-server ]]; then
    /usr/local/bin/dnstt-server -gen-key \
        -privkey-file /etc/slowdns/server.key \
        -pubkey-file /etc/slowdns/server.pub >/dev/null 2>&1 || true
    chmod 600 /etc/slowdns/server.key 2>/dev/null || true
fi
# --- config udp-custom ---
cat > /etc/udp/config.json <<'UDPJSON'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": { "mode": "passwords" }
}
UDPJSON
# --- slowdns.service (dnstt bind :5300, target dropbear :90) ---
cat > /etc/systemd/system/slowdns.service <<SDSVCEOF
[Unit]
Description=SlowDNS dnstt Server
After=network.target

[Service]
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file /etc/slowdns/server.key ns.${DOMAIN} 127.0.0.1:90
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SDSVCEOF
# --- udp-custom.service ---
cat > /etc/systemd/system/udp-custom.service <<UCSVCEOF
[Unit]
Description=UDP Custom (HTTP Custom)
After=network.target

[Service]
WorkingDirectory=/etc/udp
ExecStart=/usr/local/bin/udp-custom server -exclude 53,5300
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UCSVCEOF
# --- iptables NAT rules (urut agar 5300 & 53 aman dari catch-all) ---
cat > /etc/iptables/apply-slowdns-udp.sh <<IPTEOF
#!/bin/bash
IFACE=\$(ip route get 8.8.8.8 2>/dev/null | awk '{print \$5; exit}')
[[ -z "\$IFACE" ]] && IFACE="eth0"
iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 5300 -j ACCEPT
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 1:65535 -j REDIRECT --to-ports 36712
iptables-save > /etc/iptables/rules.v4
IPTEOF
chmod +x /etc/iptables/apply-slowdns-udp.sh
/etc/iptables/apply-slowdns-udp.sh
cat > /etc/systemd/system/iptables-restore.service <<IPTSVC
[Unit]
Description=Restore iptables NAT rules
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/apply-slowdns-udp.sh

[Install]
WantedBy=multi-user.target
IPTSVC
systemctl daemon-reload
systemctl enable --now slowdns udp-custom iptables-restore >/dev/null 2>&1 || true

ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 53/udp >/dev/null 2>&1 || true
ufw allow 53/tcp >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 8443/tcp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 8880/tcp >/dev/null 2>&1 || true
ufw allow 2052/tcp >/dev/null 2>&1 || true
ufw allow 2053/tcp >/dev/null 2>&1 || true
ufw allow 2082/tcp >/dev/null 2>&1 || true
ufw allow 2083/tcp >/dev/null 2>&1 || true
ufw allow 90/tcp >/dev/null 2>&1 || true
ufw allow 444/tcp >/dev/null 2>&1 || true
ufw allow 3128/tcp >/dev/null 2>&1 || true
ufw allow 1194/tcp >/dev/null 2>&1 || true
ufw allow 25000/udp >/dev/null 2>&1 || true
ufw allow 5300/udp >/dev/null 2>&1 || true
ufw allow 5300/tcp >/dev/null 2>&1 || true
ufw allow 36712/udp >/dev/null 2>&1 || true
ufw allow 7100:7600/tcp >/dev/null 2>&1 || true
ufw allow 9080/tcp >/dev/null 2>&1 || true
ufw allow 9088/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

systemctl daemon-reload
systemctl unmask nginx dropbear xray >/dev/null 2>&1 || true
systemctl enable --now dropbear xray vpn-ws-bridge vpn-proto-daemons nginx vpn-telegram-bot
systemctl restart dropbear xray vpn-ws-bridge vpn-proto-daemons nginx vpn-telegram-bot
chmod 700 /etc/vpn-bot 2>/dev/null || true
chmod 600 /etc/vpn-bot/vpn_data.db 2>/dev/null || true

echo "========================================================================"
echo "          INSTALASI PORTABLE SELESAI & SEMUA SERVICE AKTIF!             "
echo "========================================================================"
echo " Domain VPS      : $DOMAIN"
echo " Lokasi / ISP    : $VPS_CITY / $VPS_ISP"
echo "-----------------------------------------------------------------------"
for srv in xray dropbear nginx vpn-ws-bridge vpn-proto-daemons vpn-telegram-bot; do
    st=$(systemctl is-active "$srv" 2>/dev/null || echo dead)
    printf " %-24s : %s\n" "$srv" "$st"
done
echo "-----------------------------------------------------------------------"
echo " SlowDNS dnstt  : UDP/TCP 53 (dnstt-server)"
echo " UDP-Custom      : UDP 36712 (udp-custom)"
echo " PUB KEY        : $(cat /etc/vpn-bot/id_ed25519.pub 2>/dev/null || echo '-')"
echo "========================================================================"
""")
    os.chmod(FULL_SCRIPT_PATH, 0o755)

if __name__ == "__main__":
    note = sys.argv[1] if len(sys.argv) > 1 else "Portable Full Installer"
    build_portable_installer()
    ts_str = time.strftime("%Y-%m-%d %H:%M:%S WIB")
    caption = f"📜 Full Script Portable (setup-vpn-full.sh)\n✅ Support Ubuntu <=24.04 & Debian <=13 (Semua Spek VPS)\n✅ Tanpa Token/Admin/Domain (Siap Paste di VPS Baru)\n🕒 {ts_str}\n📌 {note}"
    ok_sent = False
    for attempt in range(3):
        try:
            res = subprocess.run(
                ["curl", "-s", "--max-time", "120", "-X", "POST",
                 f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument",
                 "-F", f"chat_id={ADMIN_ID}", "-F", f"document=@{FULL_SCRIPT_PATH}",
                 "-F", f"caption={caption}"],
                capture_output=True, text=True, timeout=150)
            body = (res.stdout or "").strip()
            # Telegram balas {"ok":true,...}; kalau bukan, catat & coba lagi
            if '"ok":true' in body.replace(" ", ""):
                ok_sent = True
                break
            print(f"Kirim backup gagal (percobaan {attempt+1}): {body[:200]}", file=sys.stderr)
        except Exception as e:
            print(f"Kirim backup error (percobaan {attempt+1}): {e}", file=sys.stderr)
        time.sleep(3 * (attempt + 1))
    if not ok_sent:
        print("Backup GAGAL terkirim ke Telegram setelah 3 percobaan.", file=sys.stderr)
        sys.exit(1)


EOF_EMBED_FILE
chmod +x /etc/vpn-bot/send_backup.py 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/vpn-bot/remote_installer.sh
#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
DOMAIN="${1:-localhost}"

# 1. Buka paksa kunci APT / DPKG
systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service apt-daily.service apt-daily-upgrade.service >/dev/null 2>&1 || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service >/dev/null 2>&1 || true
killall -9 apt apt-get dpkg unattended-upgr >/dev/null 2>&1 || true
sleep 1
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
dpkg --configure -a --force-confdef --force-confold >/dev/null 2>&1 || true

# 2. Pastikan DNS & Direktori Inti Tersedia
systemctl stop systemd-resolved >/dev/null 2>&1 || true
systemctl disable systemd-resolved >/dev/null 2>&1 || true
rm -f /etc/resolv.conf
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

mkdir -p /etc/vpn-bot /var/log/vpn-bot /etc/xray /etc/xray/certs /var/log/xray /etc/dropbear /var/www/html

# 3. Buat Swap 1GB otomatis jika RAM < 1800MB
VIRT_T=$(systemd-detect-virt 2>/dev/null || echo "kvm")
TOT_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [[ "$VIRT_T" != "openvz" && "$VIRT_T" != "lxc" ]]; then
    if [[ "${TOT_RAM:-2000}" -lt 1800 ]] && [[ $(swapon --show | wc -l) -eq 0 ]]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 >/dev/null 2>&1
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile >/dev/null 2>&1 || true
    fi
fi

# 4. Instalasi Paket secara Terpisah (Agar 1 paket gagal tidak menggagalkan Nginx)
apt-get update -y -o DPkg::Lock::Timeout=60 >/dev/null 2>&1 || true
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    nginx libnginx-mod-stream >/dev/null 2>&1 || \
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    nginx-full >/dev/null 2>&1 || \
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    nginx >/dev/null 2>&1 || true

apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    curl wget unzip openssl python3 psmisc lsof socat net-tools vnstat wondershaper >/dev/null 2>&1 || true

ufw disable >/dev/null 2>&1 || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Aktifkan firewall remote (WAJIB allow port SSH master dulu agar tak lockout)
ufw allow 22/tcp  >/dev/null 2>&1 || true
ufw allow 444/tcp >/dev/null 2>&1 || true
ufw allow 90/tcp  >/dev/null 2>&1 || true
ufw allow 80/tcp  >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 8443/tcp >/dev/null 2>&1 || true
ufw allow 9080/tcp >/dev/null 2>&1 || true
ufw allow 9088/tcp >/dev/null 2>&1 || true
ufw allow 25000/udp >/dev/null 2>&1 || true
ufw allow 5300/udp >/dev/null 2>&1 || true
ufw allow 36712/udp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

# 5. Konfigurasi OpenSSH & Dropbear 2019.78
grep -q "^/bin/false$" /etc/shells || echo "/bin/false" >> /etc/shells
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^Banner /d' /etc/ssh/sshd_config
printf "Port 22\nPort 444\nBanner /etc/issue.net\nPermitRootLogin yes\nPasswordAuthentication yes\nPubkeyAuthentication yes\n" >> /etc/ssh/sshd_config
# Ubuntu 23.10+/24.04 pakai socket activation yang hard-bind :22 & abaikan "Port".
# Matikan socket activation agar Port 444 dari sshd_config benar-benar aktif.
systemctl disable --now ssh.socket 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

systemctl stop dropbear >/dev/null 2>&1 || true
killall -9 dropbear >/dev/null 2>&1 || true
rm -f /etc/init.d/dropbear
if [[ -f /etc/vpn-bot/dropbear.bin ]]; then
    cp -f /etc/vpn-bot/dropbear.bin /usr/sbin/dropbear
    chmod +x /usr/sbin/dropbear
fi
if [[ -f /etc/vpn-bot/dropbearkey.bin ]]; then
    cp -f /etc/vpn-bot/dropbearkey.bin /usr/bin/dropbearkey
    chmod +x /usr/bin/dropbearkey
fi
[[ -f /etc/dropbear/dropbear_rsa_host_key ]] || /usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
[[ -f /etc/dropbear/dropbear_ecdsa_host_key ]] || /usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
touch /var/log/dropbear.log /var/log/vpn-ws-map.log
chmod 666 /var/log/dropbear.log /var/log/vpn-ws-map.log

cat << 'EODB' > /etc/systemd/system/dropbear.service
[Unit]
Description=Dropbear SSH Server v2019.78 (Port 90)
After=network.target
[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -EF -p 90 -W 65536 -b /etc/issue.net -r /etc/dropbear/dropbear_rsa_host_key -r /etc/dropbear/dropbear_ecdsa_host_key
StandardOutput=append:/var/log/dropbear.log
StandardError=append:/var/log/dropbear.log
KillMode=process
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
EODB

# 6. Pasang & Nyalakan Xray-Core (LimitNOFILE=65535 agar kompatibel semua kernel)
systemctl stop xray >/dev/null 2>&1 || true
killall -9 xray >/dev/null 2>&1 || true
if [[ -f /etc/vpn-bot/xray.bin ]]; then
    cp -f /etc/vpn-bot/xray.bin /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
fi
if [[ ! -x /usr/local/bin/xray ]]; then
    ARCH_R=$(uname -m)
    if [[ "$ARCH_R" == "x86_64" ]]; then AR="64"; else AR="arm64-v8a"; fi
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${AR}.zip"
    wget -qO /tmp/xray.zip "$XRAY_URL" || wget -qO /tmp/xray.zip "https://ghproxy.com/$XRAY_URL" || true
    python3 -m zipfile -e /tmp/xray.zip /usr/local/bin/ 2>/dev/null || unzip -qo /tmp/xray.zip -d /usr/local/bin/ 2>/dev/null || true
    chmod +x /usr/local/bin/xray 2>/dev/null || true
    rm -f /tmp/xray.zip
fi
if [[ ! -x /usr/local/bin/xray ]]; then
    echo "GAGAL: Xray tidak tersedia (unduh GitHub/ghproxy gagal & xray.bin tidak di-upload master)."
    echo "INSTALL_FAIL"
    exit 1
fi
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 666 /var/log/xray/*.log

cat << 'EOSVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target
[Service]
User=root
Environment=TZ=UTC
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=always
RestartSec=2
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOSVC

# 7. Pastikan Sertifikat SSL Tersedia (Sudah di-upload dari Master + Fallback lokal)
if [[ ! -s /etc/xray/certs/fullchain.pem ]] || [[ ! -s /etc/xray/certs/privkey.pem ]]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -batch \
        -keyout /etc/xray/certs/privkey.pem -out /etc/xray/certs/fullchain.pem \
        -subj "/CN=${DOMAIN}" >/dev/null 2>&1 || true
fi
chmod 644 /etc/xray/certs/fullchain.pem /etc/xray/certs/privkey.pem 2>/dev/null || true

# 8. Bebaskan Port Web & Konfigurasi Nginx (Stream + Fallback HTTP/HTTPS Murni)
systemctl stop apache2 httpd lighttpd caddy haproxy nginx >/dev/null 2>&1 || true
systemctl disable apache2 httpd lighttpd caddy haproxy >/dev/null 2>&1 || true
for p in 80 443 8080 8443 8880 2052 2053 2082 2083 10443 10444; do
    fuser -k ${p}/tcp >/dev/null 2>&1 || true
done

mkdir -p /etc/nginx/modules-enabled
if ! ls /etc/nginx/modules-enabled/*stream*.conf >/dev/null 2>&1; then
    if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]]; then
        echo "load_module /usr/lib/nginx/modules/ngx_stream_module.so;" > /etc/nginx/modules-enabled/50-mod-stream.conf
    fi
fi

rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/default
cat << 'EONGX_STREAM' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
}

stream {
    map $ssl_preread_alpn_protocols $tls_backend {
        "h2"     127.0.0.1:10443;
        default  127.0.0.1:10444;
    }

    server {
        listen 443 reuseport;
        listen 8443 reuseport;
        proxy_pass $tls_backend;
        proxy_protocol on;
        ssl_preread on;
        proxy_timeout 86400s;
    }

    server {
        listen 127.0.0.1:10444 ssl proxy_protocol reuseport;
        ssl_certificate /etc/xray/certs/fullchain.pem;
        ssl_certificate_key /etc/xray/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        proxy_pass 127.0.0.1:10015;
        proxy_protocol on;
        proxy_timeout 86400s;
    }

    server {
        listen 80 reuseport;
        listen 8080 reuseport;
        listen 8880 reuseport;
        listen 2052 reuseport;
        listen 2053 reuseport;
        listen 2082 reuseport;
        listen 2083 reuseport;
        proxy_pass 127.0.0.1:10015;
        proxy_protocol on;
        proxy_timeout 86400s;
    }
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    access_log off;
    error_log /var/log/nginx/error.log crit;

    server {
        listen 127.0.0.1:10443 ssl http2 proxy_protocol default_server reuseport;
        server_name _;

        ssl_certificate /etc/xray/certs/fullchain.pem;
        ssl_certificate_key /etc/xray/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location ^~ /vmess/ { grpc_pass grpc://127.0.0.1:10002; }
        location ^~ /vless/ { grpc_pass grpc://127.0.0.1:10005; }
        location ^~ /trojan/ { grpc_pass grpc://127.0.0.1:10008; }
        location ^~ /ss-grpc/ { grpc_pass grpc://127.0.0.1:10011; }
    }
}
EONGX_STREAM

# Jika OS remote tidak memiliki modul stream, otomatis gunakan fallback HTTP/HTTPS langsung agar Nginx 100% menyala
if ! nginx -t >/dev/null 2>&1; then
    rm -f /etc/nginx/modules-enabled/50-mod-stream.conf
    cat << 'EONGX_HTTP' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
}

http {
    sendfile on;
    tcp_nodelay on;
    keepalive_timeout 65;
    access_log off;
    error_log /var/log/nginx/error.log crit;

    server {
        listen 80 default_server;
        listen 8080;
        listen 8880;
        listen 2052;
        listen 2053;
        listen 2082;
        listen 2083;
        listen 443 ssl http2 default_server;
        listen 8443 ssl http2;
        server_name _;

        ssl_certificate /etc/xray/certs/fullchain.pem;
        ssl_certificate_key /etc/xray/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400s;

        location ^~ /vmess/ { grpc_pass grpc://127.0.0.1:10002; }
        location ^~ /vless/ { grpc_pass grpc://127.0.0.1:10005; }
        location ^~ /trojan/ { grpc_pass grpc://127.0.0.1:10008; }
        location ^~ /ss-grpc/ { grpc_pass grpc://127.0.0.1:10011; }

        location / {
            proxy_pass http://127.0.0.1:10015;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EONGX_HTTP
fi

chmod +x /etc/vpn-bot/*.py 2>/dev/null || true
cat << 'EOWSSVC' > /etc/systemd/system/vpn-ws-bridge.service
[Unit]
Description=SSH WebSocket & Xray Real-IP Bridge
After=network.target dropbear.service
[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/ws-bridge.py
Restart=always
RestartSec=2
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOWSSVC

cat << 'EOPDSVC' > /etc/systemd/system/vpn-proto-daemons.service
[Unit]
Description=VPN Auxiliary Protocols Daemon
After=network.target dropbear.service
[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/proto-daemons.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOPDSVC

IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[[ -z "$IFACE" ]] && IFACE="eth0"
systemctl enable --now vnstat >/dev/null 2>&1 || true
vnstat --add -i "$IFACE" >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl unmask dropbear xray nginx vpn-ws-bridge vpn-proto-daemons >/dev/null 2>&1 || true
systemctl enable dropbear xray vpn-ws-bridge vpn-proto-daemons nginx >/dev/null 2>&1 || true
systemctl restart dropbear xray vpn-ws-bridge vpn-proto-daemons nginx >/dev/null 2>&1 || true
sleep 2
echo "INSTALL_OK"
EOF_EMBED_FILE
chmod +x /etc/vpn-bot/remote_installer.sh 2>/dev/null || true

cat << 'EOF_EMBED_FILE' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
}

stream {
    # Single-Hop TLS: Mencatat Real-IP asli HP langsung ke WS-Bridge (10015)
    server {
        listen 443 ssl reuseport;
        listen 8443 ssl reuseport;
        ssl_certificate /etc/xray/certs/fullchain.pem;
        ssl_certificate_key /etc/xray/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_session_cache shared:STREAM_SSL:10m;
        proxy_pass 127.0.0.1:10015;
        proxy_protocol on;
        proxy_timeout 86400s;
    }

    # Single-Hop NTLS (HTTP WS / Payload): Mencatat Real-IP asli HP langsung ke WS-Bridge (10015)
    server {
        listen 80 reuseport;
        listen 8080 reuseport;
        listen 8880 reuseport;
        listen 2052 reuseport;
        listen 2053 reuseport;
        listen 2082 reuseport;
        listen 2083 reuseport;
        proxy_pass 127.0.0.1:10015;
        proxy_protocol on;
        proxy_timeout 86400s;
    }
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    access_log off;
    error_log /var/log/nginx/error.log crit;

    server {
        listen 127.0.0.1:10443 ssl http2 default_server reuseport;
        listen 2096 ssl http2 reuseport;
        server_name __DOMAIN__ _;

        ssl_certificate /etc/xray/certs/fullchain.pem;
        ssl_certificate_key /etc/xray/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;

        location ^~ /vmess/ { grpc_pass grpc://127.0.0.1:10002; }
        location ^~ /vless/ { grpc_pass grpc://127.0.0.1:10005; }
        location ^~ /trojan/ { grpc_pass grpc://127.0.0.1:10008; }
        location ^~ /ss-grpc/ { grpc_pass grpc://127.0.0.1:10011; }
    }
}

EOF_EMBED_FILE
chmod +x /etc/nginx/nginx.conf 2>/dev/null || true

# 3. Konfigurasi SSH, Dropbear 2019.78 & Unit Service Lengkap
echo "[3/6] Mengompilasi Dropbear v2019.78 & menyiapkan service..."
grep -q "^/bin/false$" /etc/shells || echo "/bin/false" >> /etc/shells
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^Banner /d' /etc/ssh/sshd_config
echo -e "Port 22\nPort 444\nBanner /etc/issue.net\nPermitRootLogin yes\nPasswordAuthentication yes\nPubkeyAuthentication yes" >> /etc/ssh/sshd_config
systemctl disable --now ssh.socket 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

cd /tmp && rm -rf dropbear-2019.78*
if wget -q --timeout=15 "https://matt.ucc.asn.au/dropbear/releases/dropbear-2019.78.tar.bz2" -O dropbear-2019.78.tar.bz2 || \
   wget -q --timeout=15 "https://dropbear.nl/mirror/releases/dropbear-2019.78.tar.bz2" -O dropbear-2019.78.tar.bz2; then
    tar -xjf dropbear-2019.78.tar.bz2 && cd dropbear-2019.78
    if ./configure CFLAGS="-O2 -fcommon -Wno-error -Wno-unused-result" --prefix=/usr --sysconfdir=/etc/dropbear >/dev/null 2>&1; then
        if make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j2 >/dev/null 2>&1; then
            systemctl stop dropbear >/dev/null 2>&1 || true
            killall -9 dropbear >/dev/null 2>&1 || true
            cp -f dropbear /usr/sbin/dropbear && cp -f dbclient dropbearkey dropbearconvert /usr/bin/
            chmod +x /usr/sbin/dropbear /usr/bin/dropbearkey
            apt-mark hold dropbear dropbear-bin >/dev/null 2>&1 || true
        fi
    fi
fi
cd /root && rm -rf /tmp/dropbear-2019.78*
[[ -f /etc/dropbear/dropbear_rsa_host_key ]] || /usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
[[ -f /etc/dropbear/dropbear_ecdsa_host_key ]] || /usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
touch /var/log/dropbear.log /var/log/vpn-ws-map.log && chmod 666 /var/log/dropbear.log /var/log/vpn-ws-map.log

systemctl stop dropbear >/dev/null 2>&1 || true
rm -f /etc/init.d/dropbear
cat << 'EODBSVC' > /etc/systemd/system/dropbear.service
[Unit]
Description=Dropbear SSH Server v2019.78 (Port 90)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -EF -p 90 -W 65536 -b /etc/issue.net -r /etc/dropbear/dropbear_rsa_host_key -r /etc/dropbear/dropbear_ecdsa_host_key
StandardOutput=append:/var/log/dropbear.log
StandardError=append:/var/log/dropbear.log
KillMode=process
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EODBSVC

# 4. Instalasi Xray-Core & Sertifikat SSL
echo "[4/6] Memasang Xray-Core & Sertifikat SSL..."
if ! fetch_xray "$ARCH"; then
    echo "GAGAL: Tidak bisa mengunduh Xray dari semua sumber."
    echo "Solusi: upload manual binary ke /root/xray-linux-${ARCH}.zip lalu jalankan ulang."
    exit 1
fi
unzip -qo /tmp/xray.zip -d /usr/local/bin/ && chmod +x /usr/local/bin/xray && rm -f /tmp/xray.zip
touch /var/log/xray/access.log /var/log/xray/error.log && chmod 666 /var/log/xray/*.log

cat << 'EOXRAY' > /etc/xray/config.json
{
  "log": { "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info" },
  "inbounds": [
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 10001, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } } },
    { "tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10002, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vmess" } } },
    { "tag": "vmess-up", "listen": "127.0.0.1", "port": 10003, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvmess" } } },
    { "tag": "vless-ws", "listen": "127.0.0.1", "port": 10004, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } } },
    { "tag": "vless-grpc", "listen": "127.0.0.1", "port": 10005, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless" } } },
    { "tag": "vless-up", "listen": "127.0.0.1", "port": 10006, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvless" } } },
    { "tag": "trojan-ws", "listen": "127.0.0.1", "port": 10007, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" } } },
    { "tag": "trojan-grpc", "listen": "127.0.0.1", "port": 10008, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "trojan" } } },
    { "tag": "trojan-up", "listen": "127.0.0.1", "port": 10009, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/uptrojan" } } },
    { "tag": "ss-ws", "listen": "127.0.0.1", "port": 10010, "protocol": "shadowsocks", "settings": { "method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/ss-ws" } } },
    { "tag": "ss-grpc", "listen": "127.0.0.1", "port": 10011, "protocol": "shadowsocks", "settings": { "method": "chacha20-ietf-poly1305", "password": "sunek-ss-default-key", "network": "tcp,udp" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "ss-grpc" } } }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": {} },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ],
  "routing": { "domainStrategy": "AsIs", "rules": [ { "type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked" } ] }
}
EOXRAY

cat << 'EOSVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
Environment=TZ=UTC
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=always
RestartSec=1
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOSVC

systemctl stop nginx >/dev/null 2>&1 || true
if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}" >/dev/null 2>&1; then
    cp -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/xray/certs/fullchain.pem
    cp -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/xray/certs/privkey.pem
else
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/xray/certs/privkey.pem -out /etc/xray/certs/fullchain.pem -subj "/CN=${DOMAIN}" >/dev/null 2>&1
fi
chmod 644 /etc/xray/certs/fullchain.pem /etc/xray/certs/privkey.pem

# 5. Konfigurasi Nginx Stream & Systemd Services
echo "[5/6] Mengonfigurasi Nginx Stream & Systemd Services..."
mkdir -p /etc/nginx/modules-enabled
if ! ls /etc/nginx/modules-enabled/*stream*.conf >/dev/null 2>&1; then
    if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]]; then
        echo "load_module /usr/lib/nginx/modules/ngx_stream_module.so;" > /etc/nginx/modules-enabled/50-mod-stream.conf
    fi
fi
rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/default
sed -i "s/__DOMAIN__/${DOMAIN}/g" /etc/nginx/nginx.conf
if [[ ! -f /proc/net/if_inet6 ]] || [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null) == "1" ]]; then
    sed -i '/listen \[\:\:\]:/d' /etc/nginx/nginx.conf
fi

cat << 'EOWSSVC' > /etc/systemd/system/vpn-ws-bridge.service
[Unit]
Description=SSH WebSocket & Xray Real-IP Bridge
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/ws-bridge.py
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOWSSVC

cat << 'EOPDSVC' > /etc/systemd/system/vpn-proto-daemons.service
[Unit]
Description=VPN Auxiliary Protocols Daemon
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /etc/vpn-bot/proto-daemons.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOPDSVC

cat << 'EOBOTSVC' > /etc/systemd/system/vpn-telegram-bot.service
[Unit]
Description=Telegram VPN Community Bot
After=network.target xray.service dropbear.service

[Service]
Type=simple
WorkingDirectory=/etc/vpn-bot
ExecStart=/etc/vpn-bot/venv/bin/python /etc/vpn-bot/bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOBOTSVC

# 6. Buat Virtualenv Python & Aktifkan Semua Layanan
echo "[6/6] Menyiapkan Python Virtualenv & menyalakan seluruh layanan..."
python3 -m venv /etc/vpn-bot/venv
/etc/vpn-bot/venv/bin/pip install -U pip aiogram paramiko aiohttp >/dev/null

IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[[ -z "$IFACE" ]] && IFACE="eth0"
systemctl enable --now vnstat >/dev/null 2>&1 || true
vnstat --add -i "$IFACE" >/dev/null 2>&1 || true

# ===== SlowDNS (dnstt) + UDP-Custom auto-install =====
echo "[6/6b] Memasang SlowDNS (dnstt) & UDP-Custom..."
ARCH_X=$(uname -m)
case "$ARCH_X" in x86_64) XARCH="amd64";; aarch64|arm64) XARCH="arm64";; *) XARCH="amd64";; esac
mkdir -p /etc/slowdns /etc/udp /etc/iptables
# --- dnstt-server ---
if [[ ! -x /usr/local/bin/dnstt-server ]]; then
    wget -qO /usr/local/bin/dnstt-server \
        "https://github.com/net2share/dnstt/releases/download/latest/dnstt-server-linux-${XARCH}" \
        2>/dev/null || true
    chmod +x /usr/local/bin/dnstt-server 2>/dev/null || true
fi
# --- udp-custom ---
if [[ ! -x /usr/local/bin/udp-custom ]]; then
    UC_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
    if [[ "$XARCH" == "arm64" ]]; then
        UC_URL="https://raw.githubusercontent.com/fisabiliyusri/Mantap/main/udp-custom/udp-custom-linux-arm"
    fi
    wget -qO /usr/local/bin/udp-custom "$UC_URL" 2>/dev/null || true
    chmod +x /usr/local/bin/udp-custom 2>/dev/null || true
fi
# --- systemd-resolved: matikan agar :53 bebas ---
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
# --- generate key dnstt (sekali saja) ---
if [[ ! -f /etc/slowdns/server.pub && -x /usr/local/bin/dnstt-server ]]; then
    /usr/local/bin/dnstt-server -gen-key \
        -privkey-file /etc/slowdns/server.key \
        -pubkey-file /etc/slowdns/server.pub >/dev/null 2>&1 || true
    chmod 600 /etc/slowdns/server.key 2>/dev/null || true
fi
# --- config udp-custom ---
cat > /etc/udp/config.json <<'UDPJSON'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": { "mode": "passwords" }
}
UDPJSON
# --- slowdns.service (dnstt bind :5300, target dropbear :90) ---
cat > /etc/systemd/system/slowdns.service <<SDSVCEOF
[Unit]
Description=SlowDNS dnstt Server
After=network.target

[Service]
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file /etc/slowdns/server.key ns.${DOMAIN} 127.0.0.1:90
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SDSVCEOF
# --- udp-custom.service ---
cat > /etc/systemd/system/udp-custom.service <<UCSVCEOF
[Unit]
Description=UDP Custom (HTTP Custom)
After=network.target

[Service]
WorkingDirectory=/etc/udp
ExecStart=/usr/local/bin/udp-custom server -exclude 53,5300
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UCSVCEOF
# --- iptables NAT rules (urut agar 5300 & 53 aman dari catch-all) ---
cat > /etc/iptables/apply-slowdns-udp.sh <<IPTEOF
#!/bin/bash
IFACE=\$(ip route get 8.8.8.8 2>/dev/null | awk '{print \$5; exit}')
[[ -z "\$IFACE" ]] && IFACE="eth0"
iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 5300 -j ACCEPT
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 1:65535 -j REDIRECT --to-ports 36712
iptables-save > /etc/iptables/rules.v4
IPTEOF
chmod +x /etc/iptables/apply-slowdns-udp.sh
/etc/iptables/apply-slowdns-udp.sh
cat > /etc/systemd/system/iptables-restore.service <<IPTSVC
[Unit]
Description=Restore iptables NAT rules
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/apply-slowdns-udp.sh

[Install]
WantedBy=multi-user.target
IPTSVC
systemctl daemon-reload
systemctl enable --now slowdns udp-custom iptables-restore >/dev/null 2>&1 || true

ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 53/udp >/dev/null 2>&1 || true
ufw allow 53/tcp >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 8443/tcp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 8880/tcp >/dev/null 2>&1 || true
ufw allow 2052/tcp >/dev/null 2>&1 || true
ufw allow 2053/tcp >/dev/null 2>&1 || true
ufw allow 2082/tcp >/dev/null 2>&1 || true
ufw allow 2083/tcp >/dev/null 2>&1 || true
ufw allow 90/tcp >/dev/null 2>&1 || true
ufw allow 444/tcp >/dev/null 2>&1 || true
ufw allow 3128/tcp >/dev/null 2>&1 || true
ufw allow 1194/tcp >/dev/null 2>&1 || true
ufw allow 25000/udp >/dev/null 2>&1 || true
ufw allow 5300/udp >/dev/null 2>&1 || true
ufw allow 5300/tcp >/dev/null 2>&1 || true
ufw allow 36712/udp >/dev/null 2>&1 || true
ufw allow 7100:7600/tcp >/dev/null 2>&1 || true
ufw allow 9080/tcp >/dev/null 2>&1 || true
ufw allow 9088/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

systemctl daemon-reload
systemctl unmask nginx dropbear xray >/dev/null 2>&1 || true
systemctl enable --now dropbear xray vpn-ws-bridge vpn-proto-daemons nginx vpn-telegram-bot
systemctl restart dropbear xray vpn-ws-bridge vpn-proto-daemons nginx vpn-telegram-bot
chmod 700 /etc/vpn-bot 2>/dev/null || true
chmod 600 /etc/vpn-bot/vpn_data.db 2>/dev/null || true

echo "========================================================================"
echo "          INSTALASI PORTABLE SELESAI & SEMUA SERVICE AKTIF!             "
echo "========================================================================"
echo " Domain VPS      : $DOMAIN"
echo " Lokasi / ISP    : $VPS_CITY / $VPS_ISP"
echo "-----------------------------------------------------------------------"
for srv in xray dropbear nginx vpn-ws-bridge vpn-proto-daemons vpn-telegram-bot; do
    st=$(systemctl is-active "$srv" 2>/dev/null || echo dead)
    printf " %-24s : %s\n" "$srv" "$st"
done
echo "-----------------------------------------------------------------------"
echo " SlowDNS dnstt  : UDP/TCP 53 (dnstt-server)"
echo " UDP-Custom      : UDP 36712 (udp-custom)"
echo " PUB KEY        : $(cat /etc/vpn-bot/id_ed25519.pub 2>/dev/null || echo '-')"
echo "========================================================================"
