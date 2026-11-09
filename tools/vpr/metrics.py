"""Aggregation of filtering events with small-cell suppression, and dataset commitments.

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
from datetime import date
from typing import Iterable

from . import merkle
from .hashing import keccak256, to_hex

DEFAULT_K = 10


FORMAT = "vpr-dataset/2"
LEAF_PREFIX = b"\x00"
EPOCH = date(1970, 1, 1)


def day_number(day: str) -> int:
    """Days since 1970-01-01 (UTC) for an ISO date, as used on-chain."""
    try:
        return (date.fromisoformat(day) - EPOCH).days
    except ValueError as e:
        raise ValueError(f"day must be an ISO date (YYYY-MM-DD): {day!r}") from e


@dataclass(frozen=True, order=True)
class Row:
    school_id: str
    day: str  # ISO date, UTC
    category: str
    count: int

    def leaf(self) -> bytes:
        """Leaf (format 2): keccak256(0x00 || day:uint32 || count:uint256 || len:uint16 || school || len:uint16 || category).

        Identical to MetricsAnchor.leafHash. Length prefixes make the encoding unambiguous, and the day is the
        on-chain day number, so a row cannot be verified against another day's root.
        """
        school = self.school_id.encode("utf-8")
        cat = self.category.encode("utf-8")
        if not school or not cat or len(school) > 0xFFFF or len(cat) > 0xFFFF:
            raise ValueError("school_id and category must be 1..65535 bytes")
        if self.count < 1:
            raise ValueError("count must be positive")
        return keccak256(
            LEAF_PREFIX
            + day_number(self.day).to_bytes(4, "big")
            + self.count.to_bytes(32, "big")
            + len(school).to_bytes(2, "big")
            + school
            + len(cat).to_bytes(2, "big")
            + cat
        )


def validate_release(rows: list[Row], k: int | None = None) -> None:
    """Checks a daily release before it is committed or verified: one day, unique cells, counts >= k."""
    if not rows:
        raise ValueError("empty release")
    days = {r.day for r in rows}
    if len(days) != 1:
        raise ValueError(f"a release covers exactly one day, got {sorted(days)}")
    day_number(rows[0].day)
    cells = [(r.school_id, r.day, r.category) for r in rows]
    if len(cells) != len(set(cells)):
        raise ValueError("duplicate (school_id, day, category) cells")
    floor = k if k is not None else 1
    bad = [r for r in rows if r.count < floor]
    if bad:
        raise ValueError(f"cells below the release threshold: {bad[:3]}")


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
    validate_release(rows)
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


def to_json(rows: list[Row], k: int) -> str:
    """Public summary of a release. The number of suppressed cells is deliberately not published."""
    return json.dumps(
        {
            "format": FORMAT,
            "k": k,
            "root": dataset_root(rows) if rows else None,
            "rows": [r.__dict__ for r in rows],
        },
        indent=2,
    )


def read_csv(text: str) -> list[Row]:
    reader = csv.DictReader(io.StringIO(text))
    return sorted(Row(r["school_id"], r["day"], r["category"], int(r["count"])) for r in reader)
