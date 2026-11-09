"""Command-line interface.

    python -m vpr.cli policy-hash  policies/example-primary.yaml
    python -m vpr.cli compile-rpz  policies/example-primary.yaml --feeds-dir examples/feeds --block-page block.example.org
    python -m vpr.cli aggregate    examples/events.csv --day 2026-11-01 --k 10 --out-csv dataset.csv
    python -m vpr.cli verify-root  dataset.csv 0x<root>
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from . import metrics, policy


def cmd_policy_hash(a):
    p = policy.load(a.policy)
    print(f"scope:        {p.scope}")
    print(f"scopeId:      {p.scope_id()}")
    print(f"version:      {p.doc['version']}")
    print(f"contentHash:  {p.content_hash()}")


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
        print(f"wrote {a.out}")
    else:
        sys.stdout.write(zone)


def cmd_aggregate(a):
    with open(a.events, encoding="utf-8") as f:
        events = [(r["school_id"], r["day"], r["category"]) for r in csv.DictReader(f)]
    days = sorted({e[1] for e in events})
    day = a.day or (days[0] if len(days) == 1 else None)
    if day is None:
        sys.exit(f"events span several days {days}; pass --day (a release covers exactly one day)")
    rows, _ = metrics.aggregate([e for e in events if e[1] == day], a.k)
    if not rows:
        sys.exit(f"no cell reaches k={a.k} on {day}; nothing to publish")
    if a.out_csv:
        Path(a.out_csv).write_text(metrics.to_csv(rows), encoding="utf-8")
    print(metrics.to_json(rows, a.k))


def cmd_restricted_hash(a):
    print(policy.restricted_list_hash(policy.load_feed(a.list)))


def cmd_verify_root(a):
    rows = metrics.read_csv(Path(a.dataset).read_text(encoding="utf-8"))
    got = metrics.dataset_root(rows)
    ok = got.lower() == a.root.lower()
    print(f"computed {got}\nexpected {a.root}\n{'MATCH' if ok else 'MISMATCH'}")
    sys.exit(0 if ok else 1)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="vpr")
    sub = ap.add_subparsers(required=True)

    s = sub.add_parser("policy-hash", help="validate a policy and print its on-chain identifiers")
    s.add_argument("policy")
    s.set_defaults(func=cmd_policy_hash)

    s = sub.add_parser("compile-rpz", help="compile a policy into an RPZ zone")
    s.add_argument("policy")
    s.add_argument("--feeds-dir", help="directory of <category>.txt domain lists")
    s.add_argument("--restricted", help="restricted list file (never published)")
    s.add_argument("--block-page", help="hostname of the block/appeal page")
    s.add_argument("--out")
    s.add_argument("--allow-missing-feeds", action="store_true", help="compile even if a category has no feed (testing only)")
    s.set_defaults(func=cmd_compile_rpz)

    s = sub.add_parser("aggregate", help="aggregate one day of events, suppress cells below k and print the dataset root")
    s.add_argument("events", help="CSV with school_id,day,category (no IPs, no domains)")
    s.add_argument("--day", help="ISO date of the release; required when the events span several days")
    s.add_argument("--k", type=int, default=metrics.DEFAULT_K)
    s.add_argument("--out-csv")
    s.set_defaults(func=cmd_aggregate)

    s = sub.add_parser("restricted-hash", help="print the commitment of a restricted list file (never publish the list)")
    s.add_argument("list")
    s.set_defaults(func=cmd_restricted_hash)

    s = sub.add_parser("verify-root", help="recompute a published dataset's root")
    s.add_argument("dataset")
    s.add_argument("root")
    s.set_defaults(func=cmd_verify_root)

    a = ap.parse_args(argv)
    a.func(a)


if __name__ == "__main__":
    main()
