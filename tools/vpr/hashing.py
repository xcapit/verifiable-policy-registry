"""Keccak-256 helpers (Ethereum's hash, not NIST SHA3-256)."""

from Crypto.Hash import keccak


def keccak256(data: bytes) -> bytes:
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


def to_hex(b: bytes) -> str:
    return "0x" + b.hex()


def from_hex(s: str) -> bytes:
    return bytes.fromhex(s[2:] if s.startswith("0x") else s)
