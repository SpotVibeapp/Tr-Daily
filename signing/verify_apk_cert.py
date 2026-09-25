#!/usr/bin/env python3
"""Fail unless an APK is signed with the committed sideload certificate.

Android will not update an app when the new APK uses a different key. CI used
to create a fresh debug key on every runner, so Install left the old app in
place. This check stops that from shipping again.
"""

from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path


def _u32(buf: bytes, i: int) -> tuple[int, int]:
    return struct.unpack_from("<I", buf, i)[0], i + 4


def certificate_sha256(apk: bytes) -> str:
    eocd = apk.rfind(b"PK\x05\x06", max(0, len(apk) - 65557))
    if eocd < 0:
        raise SystemExit("APK has no zip end record")
    cd_off = struct.unpack_from("<I", apk, eocd + 16)[0]
    footer = cd_off - 24
    if apk[footer + 8 : footer + 24] != b"APK Sig Block 42":
        raise SystemExit("APK has no v2 signing block")
    block_size = struct.unpack_from("<Q", apk, footer)[0]
    p = cd_off - (block_size + 8) + 8
    end = footer
    v2 = None
    while p + 12 <= end:
        ln = struct.unpack_from("<Q", apk, p)[0]
        pid = struct.unpack_from("<I", apk, p + 8)[0]
        if pid == 0x7109871A:
            v2 = apk[p + 12 : p + 8 + ln]
            break
        p += 8 + ln
    if v2 is None:
        raise SystemExit("APK is not v2-signed")

    i = 0
    _, i = _u32(v2, i)  # signers sequence length
    signer_len, i = _u32(v2, i)
    signer = v2[i : i + signer_len]
    j = 0
    sd_len, j = _u32(signer, j)
    signed = signer[j : j + sd_len]
    k = 0
    dig_len, k = _u32(signed, k)
    k += dig_len
    certs_len, k = _u32(signed, k)
    blob = signed[k : k + certs_len]
    n, c = _u32(blob, 0)
    cert = blob[c : c + n]
    if not cert or cert[0] != 0x30:
        raise SystemExit("could not read the signing certificate")
    return hashlib.sha256(cert).hexdigest()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} <apk> <expected-sha256-file>")
    actual = certificate_sha256(Path(sys.argv[1]).read_bytes())
    expected = Path(sys.argv[2]).read_text().strip().lower()
    print(f"apk cert sha256 {actual}")
    if actual != expected:
        raise SystemExit(
            "APK signing certificate does not match signing/CERT.sha256. "
            "Refusing to publish a build the phone cannot install over the last one."
        )
    print("signing certificate matches the committed sideload key")


if __name__ == "__main__":
    main()
