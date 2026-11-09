"""Command-line interface.

    vpr policy-hash      policies/example-primary.yaml
    vpr compile-rpz      policies/example-primary.yaml --feeds-dir examples/feeds --block-page block.example.org
    vpr evaluate         zone.rpz bad-malware.example wikipedia.org
    vpr aggregate        examples/events.csv --day 2026-11-01 --k 10 --out-csv dataset.csv
    vpr verify-root      dataset.csv 0x<root>
    vpr prove-row        dataset.csv --index 0
    vpr verify-row       proof.json
    vpr restricted-hash  restricted.txt

Exit codes: 0 success; 1 verification failed (mismatching root or proof); 2 invalid input or usage.
With --json, results are printed as a single JSON object on stdout. Errors go to stderr and never echo
dataset values.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import metrics, policy, toolkit

EXIT_OK, EXIT_MISMATCH, EXIT_INVALID = 0, 1, 2


def _out(a, obj: dict, text: str) -> None:
    print(json.dumps(obj, indent=2) if getattr(a, "json", False) else text)


def cmd_policy_hash(a):
    p = policy.load(a.policy)
    obj = {"scope": p.scope, "scopeId": p.scope_id(), "version": p.doc["version"], "contentHash": p.content_hash()}
    _out(a, obj, "\n".join(f"{k + ':':<13} {v}" for k, v in obj.items()))
    return EXIT_OK


def cmd_compile_rpz(a):
    p = policy.load(a.policy)
    feeds = {}
    if a.feeds_dir:
        for f in Path(a.feeds_dir).glob("*.txt"):
            feeds[f.stem] = policy.load_feed(f)
    restricted = policy.load_feed(a.restricted) if a.restricted else None
    zone = policy.compile_rpz(p, feeds, restricted, a.block_page, allow_missing_feeds=a.allow_missing_feeds)
    if a.out:
        Path(a.out).write_text(zone, encoding="utf-8")
        print(f"wrote {a.out}", file=sys.stderr)
    else:
        sys.stdout.write(zone)
    return EXIT_OK


def cmd_evaluate(a):
    zone = Path(a.zone).read_text(encoding="utf-8")
    results = [policy.evaluate_zone(zone, d) for d in a.domains]
    _out(a, {"zone": a.zone, "results": results}, "\n".join(f"{r['action']:<9} {r['domain']}  ({r['rule'] or 'no rule'})" for r in results))
    return EXIT_OK


def cmd_aggregate(a):
    events = metrics.read_events(Path(a.events).read_text(encoding="utf-8"))
    days = sorted({e[1] for e in events})
    day = a.day or (days[0] if len(days) == 1 else None)
    if day is None:
        raise ValueError("events span several days; pass --day (a release covers exactly one day)")
    rows = toolkit.aggregate([e for e in events if e[1] == day], a.k)
    if not rows:
        raise ValueError(f"no cell reaches k={a.k} on {day}; nothing to publish")
    if a.out_csv:
        Path(a.out_csv).write_text(metrics.to_csv(rows, a.unit_column), encoding="utf-8")
    print(metrics.to_json(rows, a.k, a.unit_column))
    return EXIT_OK


def cmd_verify_root(a):
    rows = toolkit.read_release(Path(a.dataset).read_text(encoding="utf-8"))
    got = toolkit.release_root(rows)
    ok = got.lower() == a.root.lower()
    _out(a, {"computed": got, "expected": a.root, "match": ok}, f"computed {got}\nexpected {a.root}\n{'MATCH' if ok else 'MISMATCH'}")
    return EXIT_OK if ok else EXIT_MISMATCH


def cmd_prove_row(a):
    rows = toolkit.read_release(Path(a.dataset).read_text(encoding="utf-8"))
    if not 0 <= a.index < len(rows):
        raise ValueError("index out of range")
    r = rows[a.index]
    obj = {
        "format": toolkit.DATASET_FORMAT,
        "row": {"unit_id": r.school_id, "day": r.day, "category": r.category, "count": r.count},
        "dayNumber": toolkit.day_number(r.day),
        "leaf": toolkit.leaf_hash(r),
        "proof": toolkit.row_proof(rows, a.index),
        "root": toolkit.release_root(rows),
    }
    print(json.dumps(obj, indent=2))
    return EXIT_OK


def cmd_verify_row(a):
    obj = json.loads(Path(a.proof).read_text(encoding="utf-8"))
    row = obj["row"]
    r = toolkit.Row(row["unit_id"], row["day"], row["category"], int(row["count"]))
    root = a.root or obj["root"]
    ok = toolkit.verify_row(r, obj["proof"], root)
    _out(a, {"root": root, "match": ok}, "MATCH" if ok else "MISMATCH")
    return EXIT_OK if ok else EXIT_MISMATCH


def cmd_restricted_hash(a):
    print(policy.restricted_list_hash(policy.load_feed(a.list)))
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="vpr", description="Verifiable Policy Registry tools (toolkit API v1)")
    sub = ap.add_subparsers(required=True)

    s = sub.add_parser("policy-hash", help="validate a policy and print its on-chain identifiers")
    s.add_argument("policy")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_policy_hash)

    s = sub.add_parser("compile-rpz", help="compile a policy into an RPZ zone (fails closed)")
    s.add_argument("policy")
    s.add_argument("--feeds-dir", help="directory of <category>.txt domain lists")
    s.add_argument("--restricted", help="restricted list file (never published)")
    s.add_argument("--block-page", help="hostname of the block/appeal page")
    s.add_argument("--out")
    s.add_argument("--allow-missing-feeds", action="store_true", help="compile even if a category has no feed (testing only)")
    s.set_defaults(func=cmd_compile_rpz)

    s = sub.add_parser("evaluate", help="evaluate domains against a compiled zone (zone evaluation, not DNS resolution)")
    s.add_argument("zone")
    s.add_argument("domains", nargs="+")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_evaluate)

    s = sub.add_parser("aggregate", help="aggregate one day of events, suppress cells below k and print the release root")
    s.add_argument("events", help="CSV with <unit>,day,category only (unit = school_id or unit_id)")
    s.add_argument("--day", help="ISO date of the release; required when the events span several days")
    s.add_argument("--k", type=int, default=metrics.DEFAULT_K)
    s.add_argument("--unit-column", default="school_id", choices=metrics.UNIT_COLUMNS)
    s.add_argument("--out-csv")
    s.set_defaults(func=cmd_aggregate)

    s = sub.add_parser("restricted-hash", help="print the commitment of a restricted list file (never publish the list)")
    s.add_argument("list")
    s.set_defaults(func=cmd_restricted_hash)

    s = sub.add_parser("verify-root", help="recompute a published release's root")
    s.add_argument("dataset")
    s.add_argument("root")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_verify_root)

    s = sub.add_parser("prove-row", help="print the row, leaf, proof and root for one published row (JSON)")
    s.add_argument("dataset")
    s.add_argument("--index", type=int, required=True)
    s.set_defaults(func=cmd_prove_row)

    s = sub.add_parser("verify-row", help="verify a row proof produced by prove-row, optionally against an anchored root")
    s.add_argument("proof")
    s.add_argument("--root", help="root to check against (e.g. read from MetricsAnchor); defaults to the root in the file")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_verify_row)
    return ap


def main(argv=None):
    a = build_parser().parse_args(argv)
    try:
        code = a.func(a)
    except (policy.PolicyError, ValueError, KeyError, OSError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        code = EXIT_INVALID
    sys.exit(code)


if __name__ == "__main__":
    main()
