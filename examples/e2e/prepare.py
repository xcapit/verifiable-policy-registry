# SPDX-License-Identifier: AGPL-3.0-only
"""Off-chain half of the end-to-end demo.

Hashes the example policy, aggregates one day of example events with small-cell suppression,
and writes everything the on-chain half needs (contracts/scripts/e2e.js) to a JSON file.
"""

from __future__ import annotations

import argparse
import csv
import json
from datetime import date
from pathlib import Path

from vpr import metrics, policy
from vpr.hashing import to_hex


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--events", required=True)
    ap.add_argument("--day", required=True, help="ISO date to aggregate, e.g. 2026-11-01")
    ap.add_argument("--k", type=int, default=metrics.DEFAULT_K)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()

    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    p = policy.load(a.policy)
    with open(a.events, encoding="utf-8") as f:
        events = [(r["school_id"], r["day"], r["category"]) for r in csv.DictReader(f) if r["day"] == a.day]
    rows, suppressed = metrics.aggregate(events, a.k)
    if not rows:
        raise SystemExit(f"no cell reaches k={a.k} on {a.day}")

    (out / "dataset.csv").write_text(metrics.to_csv(rows), encoding="utf-8")
    first = rows[0]
    tampered = metrics.Row(first.school_id, first.day, first.category, first.count + 1)

    data = {
        "scope": p.scope,
        "scopeId": p.scope_id(),
        "contentHash": p.content_hash(),
        "policyUri": "ipfs://example-policy",
        "validDays": int(p.doc.get("valid_days", 90)),
        "reasonCode": int(p.doc.get("reason_code", 1)),
        "day": a.day,
        "dayNumber": (date.fromisoformat(a.day) - date(1970, 1, 1)).days,
        "k": a.k,
        "suppressedCells": suppressed,
        "root": metrics.dataset_root(rows),
        "datasetUri": "ipfs://example-dataset",
        "row": first.__dict__,
        "leaf": to_hex(first.leaf()),
        "proof": metrics.row_proof(rows, 0),
        "tamperedRow": tampered.__dict__,
        "tamperedLeaf": to_hex(tampered.leaf()),
    }
    (out / "e2e.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"policy  {p.scope}  contentHash {data['contentHash']}")
    print(f"day     {a.day} (day {data['dayNumber']})  rows {len(rows)}  suppressed cells {suppressed}  k {a.k}")
    print(f"root    {data['root']}")


if __name__ == "__main__":
    main()
