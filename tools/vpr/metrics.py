"""k-anonymous aggregation of filtering events and dataset commitments.

Input events carry only (school_id, day, category). The resolver must never pass client IPs,
device identifiers or queried names to this module: privacy is enforced by what is collected,
not by what is deleted later.

Cells (school, day, category) with fewer than `k` events are suppressed before publication, so
small counts cannot be used to single out a child. The published dataset is committed to with a
Merkle root anchored daily in MetricsAnchor.sol.
"""

from __future__ import annotations

import csv
import io
import json
from collections import Counter
from dataclasses import dataclass
from typing import Iterable

from . import merkle
from .hashing import keccak256, to_hex

DEFAULT_K = 10


@dataclass(frozen=True, order=True)
class Row:
    school_id: str
    day: str  # ISO date, UTC
    category: str
    count: int

    def leaf(self) -> bytes:
        """Leaf = keccak256 of the canonical row encoding. Fields must not contain '|'."""
        for v in (self.school_id, self.day, self.category):
            if "|" in v:
                raise ValueError(f"field contains '|': {v!r}")
        return keccak256(f"{self.school_id}|{self.day}|{self.category}|{self.count}".encode("utf-8"))


def aggregate(events: Iterable[tuple[str, str, str]], k: int = DEFAULT_K) -> tuple[list[Row], int]:
    """Count events per (school, day, category) and suppress cells below k.

    Returns (published rows sorted, number of suppressed cells).
    """
    if k < 2:
        raise ValueError("k must be at least 2")
    counts = Counter(events)
    rows, suppressed = [], 0
    for (school, day, cat), n in counts.items():
        if n >= k:
            rows.append(Row(school, day, cat, n))
        else:
            suppressed += 1
    return sorted(rows), suppressed


def dataset_root(rows: list[Row]) -> str:
    return to_hex(merkle.root([r.leaf() for r in rows]))


def row_proof(rows: list[Row], index: int) -> list[str]:
    return [to_hex(p) for p in merkle.proof([r.leaf() for r in rows], index)]


def to_csv(rows: list[Row]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["school_id", "day", "category", "count"])
    for r in rows:
        w.writerow([r.school_id, r.day, r.category, r.count])
    return buf.getvalue()


def to_json(rows: list[Row], k: int, suppressed: int) -> str:
    return json.dumps(
        {
            "k": k,
            "suppressed_cells": suppressed,
            "root": dataset_root(rows) if rows else None,
            "rows": [r.__dict__ for r in rows],
        },
        indent=2,
    )


def read_csv(text: str) -> list[Row]:
    reader = csv.DictReader(io.StringIO(text))
    return sorted(Row(r["school_id"], r["day"], r["category"], int(r["count"])) for r in reader)
