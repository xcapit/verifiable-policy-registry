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
import re
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


DAY_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
COUNT_RE = re.compile(r"[0-9]{1,30}")
# Units and categories are identifiers, never domain names, addresses or free text: no dots, colons,
# slashes or spaces. This keeps queried names and IP addresses out of a release even if an exporter is wrong.
UNIT_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
CATEGORY_RE = re.compile(r"[a-z0-9_-]{1,64}")


def day_number(day: str) -> int:
    """Days since 1970-01-01 (UTC) for a strict ISO date YYYY-MM-DD, as used on-chain (1970 or later)."""
    if not isinstance(day, str) or not DAY_RE.fullmatch(day):
        raise ValueError("day must be an ISO date YYYY-MM-DD")
    try:
        n = (date.fromisoformat(day) - EPOCH).days
    except ValueError:
        raise ValueError("day must be an ISO date YYYY-MM-DD") from None
    if not 0 <= n < 2**32:
        raise ValueError("day out of range")
    return n


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
        if not isinstance(self.count, int) or isinstance(self.count, bool) or not 1 <= self.count < 2**256:
            raise ValueError("count must be a positive integer below 2**256")
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
    if any(r.count < floor for r in rows):
        # deliberately says nothing about which cells or values: an error message must not leak them
        raise ValueError("release contains cells below the threshold")


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


def to_csv(rows: list[Row], unit_column: str = "school_id") -> str:
    if unit_column not in UNIT_COLUMNS:
        raise ValueError(f"unit_column must be one of {UNIT_COLUMNS}")
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow([unit_column, "day", "category", "count"])
    for r in rows:
        w.writerow([r.school_id, r.day, r.category, r.count])
    return buf.getvalue()


def to_json(rows: list[Row], k: int, unit_column: str = "school_id") -> str:
    """Public summary of a release. The number of suppressed cells is deliberately not published."""
    if unit_column not in UNIT_COLUMNS:
        raise ValueError(f"unit_column must be one of {UNIT_COLUMNS}")
    return json.dumps(
        {
            "format": FORMAT,
            "k": k,
            "root": dataset_root(rows) if rows else None,
            "rows": [{unit_column: r.school_id, "day": r.day, "category": r.category, "count": r.count} for r in rows],
        },
        indent=2,
    )


UNIT_COLUMNS = ("school_id", "unit_id")


def read_csv(text: str) -> list[Row]:
    """Read a published release. The unit column may be named `school_id` (school use case) or `unit_id`
    (any other use case); the leaf encoding is the same."""
    reader = csv.DictReader(io.StringIO(text))
    fields = reader.fieldnames or []
    unit = next((c for c in UNIT_COLUMNS if c in fields), None)
    if unit is None or not {"day", "category", "count"} <= set(fields):
        raise ValueError(f"release header must be <unit>,day,category,count with <unit> in {UNIT_COLUMNS}")
    rows = []
    for r in reader:
        if None in r or any(v is None for v in r.values()):
            raise ValueError("release row has the wrong number of fields")
        if not COUNT_RE.fullmatch(r["count"]):
            raise ValueError("count must be a non-negative decimal integer")
        rows.append(Row(r[unit], r["day"], r["category"], int(r["count"])))
    return sorted(rows)


def read_events(text: str) -> list[tuple[str, str, str]]:
    """Read block or service events: header <unit>,day,category with <unit> in UNIT_COLUMNS; nothing else."""
    reader = csv.DictReader(io.StringIO(text))
    fields = reader.fieldnames or []
    unit = next((c for c in UNIT_COLUMNS if c in fields), None)
    if unit is None or set(fields) != {unit, "day", "category"}:
        raise ValueError(f"event header must be exactly <unit>,day,category with <unit> in {UNIT_COLUMNS}")
    events = []
    for r in reader:
        if None in r or any(v is None for v in r.values()):
            raise ValueError("event row has the wrong number of fields")
        # error messages never include the offending value
        if not UNIT_RE.fullmatch(r[unit]):
            raise ValueError("event unit is not an identifier (letters, digits, '-' or '_', at most 64)")
        if not CATEGORY_RE.fullmatch(r["category"]):
            raise ValueError("event category is not an identifier (lowercase letters, digits, '-' or '_')")
        day_number(r["day"])
        events.append((r[unit], r["day"], r["category"]))
    return events
