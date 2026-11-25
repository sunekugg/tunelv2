#!/usr/bin/env python3
"""Self-check unit slowdns: direct-bind IP:53 + format native (tanpa dnstt-compat).

HTTP Custom (binary a4n) memakai wire format native VayDNS: ClientID 2 byte.
Flag -dnstt-compat mengubahnya jadi 8 byte -> klien HP gagal noise handshake
dengan gejala 'noise handshake: unexpected client payload' di log server.
"""
import sys

UNIT_PATH = "/root/.hermes/cache/scratch/slowdns.service.live"


def _unit() -> str:
    with open(UNIT_PATH, encoding="utf-8") as f:
        return f.read()


def test_binds_public_ip_port53():
    assert "-udp 103.155.224.145:53" in _unit(), "harus direct-bind IP:53"


def test_no_redirect_port5300():
    u = _unit()
    assert "-udp :5300" not in u, "port 5300 masih dipakai"
    assert "REDIRECT" not in u.upper(), "unit tak boleh bergantung REDIRECT"


def test_uses_native_wire_format():
    u = _unit()
    assert "-dnstt-compat" not in u, "dnstt-compat memecah klien HTTP Custom"
    assert "ns-bansos.sunekvpn.cc.cd" in u, "domain tunnel hilang"
    assert "127.0.0.1:10017" in u, "upstream mux hilang"


if __name__ == "__main__":
    tests = [test_binds_public_ip_port53, test_no_redirect_port5300,
             test_uses_native_wire_format]
    for t in tests:
        try:
            t()
            print(f"OK   {t.__name__}")
        except (AssertionError, OSError) as e:
            print(f"FAIL {t.__name__}: {e}", file=sys.stderr)
            sys.exit(1)
    print(f"\n{len(tests)} test pass.")
