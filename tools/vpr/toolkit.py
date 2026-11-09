"""Stable, use-case-independent API of the VPR verification toolkit (API version 1).

Integrators should import from this module. It contains no school- or Giga-specific logic: a release is a
table of (unit_id, day, category, count) cells with small cells suppressed, committed to by a Merkle root
that `MetricsAnchor.verifyRow` can check on-chain. See docs/toolkit/INTEGRATION_GUIDE.md for the
compatibility policy.
"""

from __future__ import annotations

import json
from typing import Any, Iterable

from . import merkle, metrics
from .hashing import from_hex, keccak256, to_hex

API_VERSION = "1"
DATASET_FORMAT = metrics.FORMAT
Row = metrics.Row


def _no_floats(obj: Any) -> None:
    if isinstance(obj, float):
        raise ValueError("canonical documents contain no floating-point numbers")
    if isinstance(obj, dict):
        for v in obj.values():
            _no_floats(v)
    elif isinstance(obj, list):
        for v in obj:
            _no_floats(v)


def canonical_json(obj: Any) -> bytes:
    """Deterministic JSON: sorted keys, no whitespace, UTF-8 (the encoding of policy and appeal documents).

    Floats and NaN are rejected, because their serialisation differs across languages. This is the
    normative form; it is not RFC 8785 (JCS).
    """
    _no_floats(obj)
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def document_hash(obj: Any) -> str:
    """keccak256 of the canonical JSON form; used for policy documents and appeal documents."""
    return to_hex(keccak256(canonical_json(obj)))


def day_number(day: str) -> int:
    return metrics.day_number(day)


def aggregate(events: Iterable[tuple[str, str, str]], k: int) -> list[Row]:
    """Count (unit_id, day, category) events and drop cells below k. The number of dropped cells is not returned."""
    rows, _ = metrics.aggregate(events, k)
    return rows


def leaf_hash(row: Row) -> str:
    return to_hex(row.leaf())


def release_root(rows: list[Row]) -> str:
    return metrics.dataset_root(rows)


def row_proof(rows: list[Row], index: int) -> list[str]:
    metrics.validate_release(rows)
    return metrics.row_proof(rows, index)


def verify_row(row: Row, proof: list[str], root: str) -> bool:
    """Off-chain equivalent of MetricsAnchor.verifyRow for an anchored root."""
    return merkle.verify(row.leaf(), [from_hex(p) for p in proof], from_hex(root))


def read_release(text: str) -> list[Row]:
    return metrics.read_csv(text)


def write_release(rows: list[Row], unit_column: str = "unit_id") -> str:
    return metrics.to_csv(rows, unit_column)
