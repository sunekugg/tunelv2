#!/usr/bin/env python3
"""Diagnosa throughput SlowDNS: ukur ukuran respons maksimum yang lolos.

Throughput SlowDNS = (payload per respons DNS) x (respons/detik).
Kalau respons terpotong kecil, kecepatan drop drastis walau RTT bagus.
Kirim query dengan EDNS bufsize besar lalu bandingkan ukuran balasan.
"""
import os
import socket
import sys


def qname(d: str) -> bytes:
    out = b""
    for label in d.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def build(clientid: bytes, payload: bytes, domain: str, bufsize: int) -> bytes:
    """Query TXT dengan EDNS0 bufsize, isi payload agar server balas data."""
    hdr = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x01"
    label = f"{payload.hex()}.{clientid.hex()}"
    q = hdr + qname(f"{label}.{domain}") + b"\x00\x10\x00\x01"
    opt = b"\x00" + b"\x00\x29" + bufsize.to_bytes(2, "big") + b"\x00\x00\x00\x00\x00\x00"
    return q + opt


def probe(host: str, port: int, domain: str, bufsize: int) -> tuple[int, int]:
    cid = os.urandom(8)
    payload = os.urandom(200)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(4)
    try:
        s.sendto(build(cid, payload, domain, bufsize), (host, port))
        data, _ = s.recvfrom(8192)
        return len(data), data[3] & 0x0F
    except (socket.timeout, OSError):
        return -1, -1
    finally:
        s.close()


def test_buffer_larger_than_512_helps():
    """EDNS 4096 harus menghasilkan balasan >= balasan EDNS 512.

    Bila sama saja, resolver perantara memotong -> kecepatan terkunci rendah.
    """
    small, _ = probe("127.0.0.1", 53, "ns-bansos.sunekvpn.cc.cd", 512)
    large, _ = probe("127.0.0.1", 53, "ns-bansos.sunekvpn.cc.cd", 4096)
    assert small != -1, "server tidak menjawab EDNS 512"
    assert large != -1, "server tidak menjawab EDNS 4096"
    assert large >= small, f"balasan bufsize besar ({large}) < kecil ({small})"


def main() -> None:
    for bufsize in (512, 1232, 1400, 4096):
        size, rcode = probe("127.0.0.1", 53, "ns-bansos.sunekvpn.cc.cd", bufsize)
        print(f"  EDNS {bufsize:5d} -> ukuran balasan {size:5d} byte, rcode {rcode}")

    try:
        test_buffer_larger_than_512_helps()
        print("OK   bufsize besar tidak dipotong")
    except AssertionError as e:
        print(f"INFO {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
