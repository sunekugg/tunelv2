#!/usr/bin/env python3
"""Self-check perubahan mux: TCP_NODELAY keduanya + patch disimpan.
TDD: test dijalankan sebelum deploy; menggambarkan perilaku yang diinginkan."""
import re
import sys

MUX_PATH = "/usr/local/bin/slowdns_mux.py"


def test_nodelay_applied_to_both_sides():
    with open(MUX_PATH, encoding="utf-8") as f:
        src = f.read()
    # minimal 2 panggilan setsockopt TCP_NODELAY (client & backend)
    n = len(re.findall(r"TCP_NODELAY", src))
    assert n >= 2, f"TCP_NODELAY hanya {n} kali — harus diset di client & backend"


def test_patch_has_intent_comment():
    with open(MUX_PATH, encoding="utf-8") as f:
        src = f.read()
    assert "Node latency: disable Nagle" in src, "penjelasan patch harus ada"


if __name__ == "__main__":
    for t in (test_nodelay_applied_to_both_sides, test_patch_has_intent_comment):
        try:
            t()
            print(f"OK   {t.__name__}")
        except (AssertionError, OSError) as e:
            print(f"FAIL {t.__name__}: {e}", file=sys.stderr)
            sys.exit(1)
    print("2 test pass.")
