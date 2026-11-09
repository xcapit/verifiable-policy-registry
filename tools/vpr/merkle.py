"""Sorted-pair keccak256 Merkle tree.

Same scheme as OpenZeppelin's MerkleProof and contracts/src/MetricsAnchor.sol#verifyLeaf:
parent = keccak256(min(a, b) || max(a, b)). Odd nodes are promoted unchanged to the next level.
"""

from __future__ import annotations

from .hashing import keccak256


def hash_pair(a: bytes, b: bytes) -> bytes:
    return keccak256(a + b) if a < b else keccak256(b + a)


def build_levels(leaves: list[bytes]) -> list[list[bytes]]:
    if not leaves:
        raise ValueError("cannot build a Merkle tree with no leaves")
    levels = [list(leaves)]
    while len(levels[-1]) > 1:
        cur = levels[-1]
        nxt = []
        for i in range(0, len(cur), 2):
            if i + 1 < len(cur):
                nxt.append(hash_pair(cur[i], cur[i + 1]))
            else:
                nxt.append(cur[i])  # promote odd node
        levels.append(nxt)
    return levels


def root(leaves: list[bytes]) -> bytes:
    return build_levels(leaves)[-1][0]


def proof(leaves: list[bytes], index: int) -> list[bytes]:
    levels = build_levels(leaves)
    path = []
    for level in levels[:-1]:
        sibling = index ^ 1
        if sibling < len(level):
            path.append(level[sibling])
        index //= 2
    return path


def verify(leaf: bytes, path: list[bytes], expected_root: bytes) -> bool:
    computed = leaf
    for p in path:
        computed = hash_pair(computed, p)
    return computed == expected_root
