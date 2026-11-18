#!/usr/bin/env python3
"""Odcisk SHA-256 certyfikatu podpisu APK (schemat v2/v3) – bez Android SDK.

Użycie:
  python3 tool/apk_cert.py plik.apk              # wypisuje odcisk
  python3 tool/apk_cert.py plik.apk OCZEKIWANY   # kod 1, gdy odcisk się różni

Odcisk certyfikatu jest publiczny (to nie jest sekret). Ten sam odcisk
w nowym APK = aktualizacja zainstaluje się na poprzednią wersję bez utraty danych.
"""
import hashlib
import struct
import sys


def _lp(b, o):
    n = struct.unpack('<I', b[o:o + 4])[0]
    return b[o + 4:o + 4 + n], o + 4 + n


def cert_sha256(path):
    d = open(path, 'rb').read()
    eocd = d.rfind(b'PK\x05\x06')
    if eocd < 0:
        raise SystemExit('To nie jest plik APK/ZIP')
    cd_off = struct.unpack('<I', d[eocd + 16:eocd + 20])[0]
    if d[cd_off - 16:cd_off] != b'APK Sig Block 42':
        raise SystemExit('APK nie ma podpisu v2/v3')
    size = struct.unpack('<Q', d[cd_off - 24:cd_off - 16])[0]
    p, end = cd_off - size - 8 + 8, cd_off - 24
    found = {}
    while p < end:
        ln = struct.unpack('<Q', d[p:p + 8])[0]
        bid = struct.unpack('<I', d[p + 8:p + 12])[0]
        val = d[p + 12:p + 8 + ln]
        p += 8 + ln
        if bid in (0x7109871a, 0xf05368c0):  # v2, v3
            signers, _ = _lp(val, 0)
            signer, _ = _lp(signers, 0)
            signed, _ = _lp(signer, 0)
            _, o = _lp(signed, 0)
            certs, _ = _lp(signed, o)
            cert, _ = _lp(certs, 0)
            found['v2' if bid == 0x7109871a else 'v3'] = hashlib.sha256(cert).hexdigest()
    if not found:
        raise SystemExit('Nie znaleziono certyfikatu podpisu')
    return found.get('v3') or found['v2']


if __name__ == '__main__':
    fp = cert_sha256(sys.argv[1])
    print(fp)
    if len(sys.argv) > 2 and fp != sys.argv[2].strip().lower():
        print('BŁĄD: inny klucz podpisu niż w poprzednich wersjach – APK nie zainstaluje się jako aktualizacja.',
              file=sys.stderr)
        sys.exit(1)
