#!/usr/bin/env python3
"""AtlasX 公开 Pro 自助签发（社区版密钥分发）。

将老发卡平台（license_gen_portal）的 AX2 签发机制做成单文件脚本，并附带
已公开的平台 Ed25519 私钥，使任何人可为本机申请码签发 Pro License。

用法：
  pip install cryptography
  python3 scripts/atlasx_public_pro_issue.py --mid AXID-XXXX-...
  # 输出 AX2-… 串 → 粘贴到 设置 → 系统 → Pro License

安全说明（刻意公开）：
  - 本私钥与产品内置公钥配对，签出的证可被正式客户端验过
  - 同一私钥亦用于官方升级包签名；公开后任何人可伪造升级包
  - 这是产品方主动开放 Pro 的决定，不是绕过
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import secrets
import sys
import zlib
from datetime import UTC, datetime, timedelta
from typing import Any

try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM, ChaCha20Poly1305
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
except ImportError:
    print("需要 cryptography：pip install cryptography", file=sys.stderr)
    raise SystemExit(2) from None

# ---- 社区公开的平台密钥（与 src/radar/license/pubkey.py 配对）----
# 32-byte raw Ed25519 private key（hex）。公开后任何人可签发 Pro / 伪造升级包。
_COMMUNITY_SK_HEX = (
    "a3af8ae15ec4a73522b90bb209104189e3d91f88297d5f6d9381ae8c55d0307c"
)
_EXPECTED_PK_B64 = "WrmWH_iFC9zvrQ4r0Qd2_PKOb1hMvPOqlGJ-ygYtJ4w"

# ---- AX2 常量（与 license_gen_portal / radar.license.codec 一致）----
PREFIX = "AX2"
MAGIC = b"AXL2"
LICENSE_FORMAT_V = 2
_SALT_LEN = 16
_NONCE_LEN = 12
_HEADER_LEN = 4 + 1 + 1 + _SALT_LEN
_DECOY_GROUPS = 3
_B32_ALPHABET = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
_AAD_L1 = b"AX2-l1"
_AAD_L2 = b"AX2-l2"
_INFO_L1 = b"ax2-l1"
_INFO_L2 = b"ax2-l2"
_INFO_L3 = b"ax2-l3"
_SEAL_DOMAIN = b"AtlasX-license-seal-v1"
_MID_RE = re.compile(r"^[0-9a-f]{32}$")


def _load_sk() -> Ed25519PrivateKey:
    raw = bytes.fromhex(_COMMUNITY_SK_HEX)
    if len(raw) != 32:
        raise RuntimeError("community sk length != 32")
    sk = Ed25519PrivateKey.from_private_bytes(raw)
    pk_b64 = base64.urlsafe_b64encode(sk.public_key().public_bytes_raw()).decode().rstrip("=")
    if pk_b64 != _EXPECTED_PK_B64:
        raise RuntimeError(f"signing key mismatch: got {pk_b64}")
    return sk


def _seal_master() -> bytes:
    pk = _load_sk().public_key().public_bytes_raw()
    return hashlib.sha256(_SEAL_DOMAIN + pk).digest()


def _derive(ikm: bytes, salt: bytes, info: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(ikm)


def _sha256_ctr(key: bytes, n: int) -> bytes:
    out = bytearray()
    counter = 0
    while len(out) < n:
        out.extend(hashlib.sha256(key + counter.to_bytes(4, "big")).digest())
        counter += 1
    return bytes(out[:n])


def _perm_indices(key: bytes, n: int) -> list[int]:
    perm = list(range(n))
    if n < 2:
        return perm
    stream = _sha256_ctr(key, (n * 3) + 8)
    pos = 0
    for i in range(n - 1, 0, -1):
        span = i + 1
        nbytes = max(1, (span.bit_length() + 7) // 8)
        if pos + nbytes > len(stream):
            stream = stream + _sha256_ctr(key + b"\x01", (n * 3) + 8 + pos + nbytes)
        v = int.from_bytes(stream[pos : pos + nbytes], "big") % span
        pos += nbytes
        perm[i], perm[v] = perm[v], perm[i]
    return perm


def _permute(data: bytes, key: bytes) -> bytes:
    perm = _perm_indices(key, len(data))
    out = bytearray(len(data))
    for i, p in enumerate(perm):
        out[p] = data[i]
    return bytes(out)


def _unpermute(data: bytes, key: bytes) -> bytes:
    perm = _perm_indices(key, len(data))
    out = bytearray(len(data))
    for i, p in enumerate(perm):
        out[i] = data[p]
    return bytes(out)


def _xor_keystream(data: bytes, key: bytes) -> bytes:
    ks = _sha256_ctr(key, len(data))
    return bytes(a ^ b for a, b in zip(data, ks))


def _mod97_hex(hex32: str) -> int:
    rem = 0
    for ch in hex32:
        rem = (rem * 16 + int(ch, 16)) % 97
    return rem


def parse_request_code(text: str) -> str:
    s = (text or "").strip().upper()
    for ch in "\r\n\t -_":
        s = s.replace(ch, "")
    if s.startswith("AXID"):
        s = s[4:]
    if len(s) == 32 and _MID_RE.fullmatch(s.lower()):
        return s.lower()
    if len(s) != 34:
        return ""
    mid, check = s[:32], s[32:]
    if not _MID_RE.fullmatch(mid.lower()) or not check.isdigit():
        return ""
    if str(_mod97_hex(mid.lower())).zfill(2) != check:
        return ""
    return mid.lower()


def seal_payload_layers(payload: dict[str, Any], *, machine_id: str, salt: bytes) -> bytes:
    mid = (machine_id or "").strip().lower()
    if not mid:
        raise ValueError("machine_id required")
    master = _seal_master()
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    k1 = _derive(master, salt, _INFO_L1)
    n1 = secrets.token_bytes(_NONCE_LEN)
    l1 = n1 + AESGCM(k1).encrypt(n1, body, _AAD_L1)
    k2 = _derive(mid.encode("utf-8"), salt, _INFO_L2)
    n2 = secrets.token_bytes(_NONCE_LEN)
    l2 = MAGIC + n2 + ChaCha20Poly1305(k2).encrypt(n2, l1, _AAD_L2)
    k3 = _derive(mid.encode("utf-8"), salt, _INFO_L3)
    return _permute(_xor_keystream(l2, k3), k3)


def _open_layers(l3: bytes, *, salt: bytes, mid: str) -> dict[str, Any]:
    k3 = _derive(mid.encode("utf-8"), salt, _INFO_L3)
    l2 = _xor_keystream(_unpermute(l3, k3), k3)
    if l2[:4] != MAGIC:
        raise ValueError("wrong_machine")
    k2 = _derive(mid.encode("utf-8"), salt, _INFO_L2)
    l1 = ChaCha20Poly1305(k2).decrypt(l2[4 : 4 + _NONCE_LEN], l2[4 + _NONCE_LEN :], _AAD_L2)
    k1 = _derive(_seal_master(), salt, _INFO_L1)
    pt = AESGCM(k1).decrypt(l1[:_NONCE_LEN], l1[_NONCE_LEN:], _AAD_L1)
    payload = json.loads(pt.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("malformed")
    return payload


def _check_group(blob: bytes) -> str:
    crc = zlib.crc32(blob) & 0xFFFF
    return base64.b32encode(crc.to_bytes(2, "big")).decode("ascii").rstrip("=")[:4]


def _decoy_positions(check: str, total: int) -> list[int]:
    positions: list[int] = []
    round_i = 0
    while len(positions) < min(_DECOY_GROUPS, max(total, 1)) and round_i < 32:
        h = hashlib.sha256(f"ax2:{check}:{round_i}".encode("ascii")).digest()
        for b in h:
            v = b % total if total else 0
            if v not in positions:
                positions.append(v)
                if len(positions) >= _DECOY_GROUPS:
                    break
        round_i += 1
    return positions


def armor_encode(blob: bytes) -> str:
    data = base64.b32encode(blob).decode("ascii").rstrip("=")
    groups = [data[i : i + 4] for i in range(0, len(data), 4)]
    check = _check_group(blob)
    total = len(groups) + _DECOY_GROUPS
    decoy_at = set(_decoy_positions(check, total))
    ks = _sha256_ctr(f"ax2-decoy:{check}".encode("ascii"), _DECOY_GROUPS * 4)
    decoy_chars = [c for c in base64.b32encode(ks).decode("ascii") if c in _B32_ALPHABET]
    out: list[str] = []
    di = 0
    for idx in range(total):
        if idx in decoy_at:
            out.append("".join(decoy_chars[di * 4 : di * 4 + 4]) or "AAAA")
            di += 1
        else:
            out.append(groups.pop(0))
    out.append(check)
    return PREFIX + "-" + "-".join(out)


def armor_decode(text: str) -> bytes | None:
    s = (text or "").strip().upper()
    for ch in "\r\n\t ":
        s = s.replace(ch, "")
    if s.startswith(PREFIX + "-"):
        s = s[len(PREFIX) + 1 :]
    elif s.startswith(PREFIX):
        s = s[len(PREFIX) :]
    if "-" not in s:
        return None
    groups = [g for g in s.split("-") if g]
    if len(groups) < _DECOY_GROUPS + 2:
        return None
    if any(not g or not set(g) <= _B32_ALPHABET for g in groups):
        return None
    check = groups[-1]
    rest = groups[:-1]
    decoy_at = set(_decoy_positions(check, len(rest)))
    data_groups = [g for i, g in enumerate(rest) if i not in decoy_at]
    b32 = "".join(data_groups)
    if not b32:
        return None
    pad = "=" * (-len(b32) % 8)
    try:
        blob = base64.b32decode(b32 + pad)
    except Exception:  # noqa: BLE001
        return None
    if _check_group(blob) != check:
        return None
    return blob


def issue_ax2(
    *,
    mid: str,
    lid: str = "",
    days: int = 3650,
    note: str = "community-public-pro",
) -> dict[str, str]:
    sk = _load_sk()
    now = datetime.now(UTC)
    iat_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    days = max(1, min(int(days), 3650))
    exp_s = (now + timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
    lid_n = re.sub(r"[^a-zA-Z0-9._-]+", "-", (lid or "").strip())[:64] or (
        f"public-{now.strftime('%Y%m%d')}-{secrets.token_hex(3)}"
    )
    payload = {
        "v": 2,
        "edition": "pro",
        "iss": "AtlasX",
        "iat": iat_s,
        "exp": exp_s,
        "lid": lid_n,
        "mid": mid,
    }
    if note.strip():
        payload["note"] = note.strip()[:200]

    salt = secrets.token_bytes(_SALT_LEN)
    l3 = seal_payload_layers(payload, machine_id=mid, salt=salt)
    body = MAGIC + bytes([LICENSE_FORMAT_V, 0]) + salt + l3
    raw = armor_encode(body + sk.sign(body))

    blob = armor_decode(raw)
    assert blob is not None and blob[:-64] == body, "armor roundtrip"
    try:
        sk.public_key().verify(blob[-64:], blob[:-64])
    except InvalidSignature:
        raise RuntimeError("self-check: signature") from None
    got = _open_layers(blob[_HEADER_LEN:-64], salt=blob[6 : 6 + _SALT_LEN], mid=mid)
    assert got.get("lid") == lid_n and got.get("mid") == mid and got.get("exp") == exp_s
    return {"raw": raw, "lid": lid_n, "mid": mid, "iat": iat_s, "exp": exp_s, "note": note.strip()}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="AtlasX 公开 Pro 自助签发（社区密钥）",
    )
    p.add_argument(
        "--mid",
        required=True,
        help="本机申请码（设置页 AXID-…）",
    )
    p.add_argument("--lid", default="", help="许可证 ID（可选）")
    p.add_argument(
        "--days",
        type=int,
        default=3650,
        help="有效天数（默认 3650≈10 年，上限 3650）",
    )
    p.add_argument("--note", default="community-public-pro", help="备注")
    p.add_argument("--json", action="store_true", help="JSON 输出")
    args = p.parse_args(argv)

    mid = parse_request_code(args.mid)
    if not mid:
        print("申请码无效：请粘贴设置页的 AXID-…（含校验位）", file=sys.stderr)
        return 1

    issued = issue_ax2(mid=mid, lid=args.lid, days=args.days, note=args.note)
    if args.json:
        print(json.dumps(issued, ensure_ascii=False, indent=2))
    else:
        print(f"lid={issued['lid']}")
        print(f"mid={issued['mid']}")
        print(f"iat={issued['iat']}")
        print(f"exp={issued['exp']}")
        print(issued["raw"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
