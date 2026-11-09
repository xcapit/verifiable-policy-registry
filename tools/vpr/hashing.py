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


def abi_encode_address_string(address: str, text: str) -> bytes:
    """Solidity abi.encode(address, string)."""
    a = bytes.fromhex(address[2:] if address.startswith("0x") else address)
    if len(a) != 20:
        raise ValueError("address must be 20 bytes")
    s = text.encode("utf-8")
    padded = s + b"\x00" * ((32 - len(s) % 32) % 32)
    return a.rjust(32, b"\x00") + (64).to_bytes(32, "big") + len(s).to_bytes(32, "big") + padded


def scope_id(governor: str, scope: str) -> str:
    """On-chain scope id: keccak256(abi.encode(governor, scope)), as VerifiablePolicyRegistry.scopeIdOf."""
    return to_hex(keccak256(abi_encode_address_string(governor, scope)))
