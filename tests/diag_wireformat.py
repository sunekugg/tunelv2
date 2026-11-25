#!/usr/bin/env python3
"""Diagnosa: binary a4n (slowdns-hc) menolak query tanpa ClientID 8 byte.
Bandingkan perilaku server: a4n vs vaydns-server, terhadap query valid & invalid.

Log a4n: 'NXDOMAIN: 6 bytes are too short to contain a ClientID'
-> server a4n BUTUH ClientID 8 byte, artinya protokol = dnstt-compat.
Klien vaydns default 2 byte -> tak cocok.
"""
import socket
import subprocess
import sys
import time

TARGET_IP = "103.155.224.145"
DOMAIN = "ns-bansos.sunekvpn.cc.cd"


def qname(domain: str) -> bytes:
    out = b""
    for label in domain.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def build(clientid: bytes, domain: str, qtype: int = 16) -> bytes:
    """Query TXT berisi ClientID + payload kosong (mimik awal handshake)."""
    hdr = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    label = clientid.hex()
    return hdr + qname(f"{label}.{domain}") + qtype.to_bytes(2, "big") + b"\x00\x01"


def send(payload: bytes, timeout: float = 3.0) -> bytes | None:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(payload, (TARGET_IP, 53))
        data, _ = s.recvfrom(4096)
        return data
    except (socket.timeout, OSError):
        return None
    finally:
        s.close()


def rcode(resp: bytes | None) -> str:
    if resp is None:
        return "TIMEOUT"
    return {0: "NOERROR", 2: "SERVFAIL", 3: "NXDOMAIN"}.get(resp[3] & 0x0F, f"RCODE{resp[3] & 0x0F}")


def test_clientid16_hex_rejected():
    """ClientID 8 byte (16 hex) -> server a4n harus menjawab (tidak timeout)."""
    resp = send(build(b"\x00" * 8, DOMAIN))
    assert resp is not None, "server tidak menjawab query ClientID 8 byte"


def test_server_answers_any_valid_query():
    """Query ke domain tunnel harus dapat balasan DNS (bukan timeout)."""
    resp = send(build(b"\xab" * 8, DOMAIN))
    assert resp is not None, "server tidak membalas"


def main() -> None:
    print(f"target {TARGET_IP}:53 domain {DOMAIN}")
    for label, cid in (("clientid 8B (dnstt)", b"\x11" * 8),
                       ("clientid 2B (native)", b"\x22" * 2)):
        resp = send(build(cid, DOMAIN))
        print(f"  {label:22} -> {rcode(resp)} ({'ada balasan' if resp else 'diam'})")
    for name, fn in (("clientid16_hex_accepted", test_clientid16_hex_rejected),
                     ("server_answers", test_server_answers_any_valid_query)):
        try:
            fn()
            print(f"OK   {name}")
        except AssertionError as e:
            print(f"FAIL {name}: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
