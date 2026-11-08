#!/usr/bin/env python3
"""Keyless *structural* SOPS dotenv-envelope validator (not authentication).

No private age keys, sops binary, or network access are needed. SOPS
uses a 32-byte encoded IV field in this dotenv format, not the 12-byte
internal GCM counter nonce; the authentication tag is 16 bytes. Valid structure
does not prove the MAC or ciphertext genuine: only SOPS decryption with a
trusted key can authenticate them. This gate rejects cheap marker spoofing.
"""
import base64
from pathlib import Path
import re
import sys

_ENC = re.compile(
    r"ENC\[AES256_GCM,data:([A-Za-z0-9+/=]*),"
    r"iv:([A-Za-z0-9+/=]+),tag:([A-Za-z0-9+/=]+),type:(str|int|float|bool|binary)\]"
)
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_AGE = re.compile(r"sops_age__list_([0-9]+)__map_(enc|recipient)")
_RECIPIENT = re.compile(r"age1[a-z0-9]{58}")
_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def fail(path: Path, reason: str) -> None:
    # Never print ciphertext, plaintext fields, or secret-like values in CI.
    raise ValueError(f"{path.name}: {reason}")


def encrypted(value: str, path: Path, field: str) -> None:
    match = _ENC.fullmatch(value)
    if not match:
        fail(path, f"invalid SOPS AES-GCM envelope for {field}")
    for name, encoded, exact_len in (
        ("data", match.group(1), None),
        ("SOPS iv", match.group(2), 32),
        ("tag", match.group(3), 16),
    ):
        try:
            decoded = base64.b64decode(encoded, validate=True)
        except (ValueError, base64.binascii.Error):
            fail(path, f"invalid base64 {name} for {field}")
        if exact_len is not None and len(decoded) != exact_len:
            fail(path, f"invalid {name} length for {field}")


def inspect(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        fail(path, "ciphertext path is a symlink or not a regular file")
    if path.stat().st_size > 1024 * 1024:
        fail(path, "ciphertext exceeds 1 MiB structural audit budget")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeError:
        fail(path, "ciphertext must be UTF-8 dotenv")
    fields: dict[str, str] = {}
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        if "=" not in line:
            fail(path, "invalid dotenv assignment")
        key, val = line.split("=", 1)
        if not _NAME.fullmatch(key):
            fail(path, "invalid dotenv key")
        if key in fields:
            fail(path, f"duplicate dotenv key {key}")
        fields[key] = val

    if "sops_mac" not in fields:
        fail(path, "missing SOPS MAC")
    encrypted(fields["sops_mac"], path, "sops_mac")
    if not _VERSION.fullmatch(fields.get("sops_version", "")):
        fail(path, "missing or invalid SOPS version")
    if not fields.get("sops_lastmodified"):
        fail(path, "missing SOPS modification timestamp")
    if not fields.get("sops_unencrypted_suffix"):
        fail(path, "missing SOPS unencrypted suffix")

    indexed: dict[int, dict[str, str]] = {}
    recipients: set[str] = set()
    for key, value in fields.items():
        match = _AGE.fullmatch(key)
        if match:
            index, kind = int(match.group(1)), match.group(2)
            indexed.setdefault(index, {})[kind] = value
        elif key.startswith("sops_"):
            continue
        else:
            # No plaintext settings can hide behind one legitimate marker.
            encrypted(value, path, key)

    if len(indexed) < 2 or sorted(indexed) != list(range(len(indexed))):
        fail(path, "needs >= 2 contiguous age recipient entries")
    for index, entry in sorted(indexed.items()):
        recipient = entry.get("recipient", "")
        if not _RECIPIENT.fullmatch(recipient):
            fail(path, f"invalid or missing age recipient at index {index}")
        if recipient in recipients:
            fail(path, "duplicate age recipient")
        recipients.add(recipient)
        body = entry.get("enc", "")
        if not (
            body.startswith(r"-----BEGIN AGE ENCRYPTED FILE-----\n")
            and body.endswith(r"\n-----END AGE ENCRYPTED FILE-----\n")
            and len(body) > 100
        ):
            fail(path, f"missing or malformed age-wrapped data at index {index}")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check-sops-envelope.py ciphertext.env.enc [...] ", file=sys.stderr)
        return 2
    try:
        for name in sys.argv[1:]:
            inspect(Path(name))
    except (ValueError, OSError) as exc:
        print(f"SOPS structural audit denied: {exc}", file=sys.stderr)
        return 1
    print(f"SOPS structural audit: {len(sys.argv) - 1} ciphertext file(s) structurally valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
