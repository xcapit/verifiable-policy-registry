"""Command-line interface.

    vpr policy-hash      policies/example-primary.yaml
    vpr compile-rpz      policies/example-primary.yaml --feeds-dir examples/feeds --block-page block.example.org
    vpr evaluate         zone.rpz bad-malware.example wikipedia.org
    vpr aggregate        examples/events.csv --day 2026-11-01 --k 10 --out-csv dataset.csv
    vpr verify-root      dataset.csv 0x<root>
    vpr prove-row        dataset.csv --index 0
    vpr verify-row       proof.json
    vpr restricted-hash  restricted.txt
    vpr check-carryover  tested-v3.yaml in-force-v5.yaml --tested-hash 0x<h3> --in-force-hash 0x<h5>
    vpr check-renewal    v4.yaml v5.yaml --reason-code 2

Exit codes: 0 success; 1 verification failed (mismatching root or proof); 2 invalid input or usage,
including any unexpected error. verify-row without --root only checks self-consistency (anchored=false).
With --json, results are printed as a single JSON object on stdout. Errors go to stderr and never echo
dataset values.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from . import metrics, policy, toolkit

EXIT_OK, EXIT_MISMATCH, EXIT_INVALID = 0, 1, 2
ROOT_RE = re.compile(r"0x[0-9a-fA-F]{64}")


def _out(a, obj: dict, text: str) -> None:
    print(json.dumps(obj, indent=2) if getattr(a, "json", False) else text)


def cmd_policy_hash(a):
    p = policy.load(a.policy)
    obj = {"scope": p.scope, "version": p.doc["version"], "contentHash": p.content_hash(), "rulesDigest": p.rules_digest()}
    if a.governor:
        obj["governor"] = a.governor
        obj["scopeId"] = p.scope_id(a.governor)
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
        # the zone contains restricted entries in clear: it is an operator-confidential file
        out = Path(a.out)
        out.touch(mode=0o600, exist_ok=True)
        out.chmod(0o600)
        out.write_text(zone, encoding="utf-8")
        print(f"wrote {a.out} (mode 0600; do not publish)", file=sys.stderr)
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
    summary = metrics.to_json(rows, a.k, a.unit_column)  # validates the release before anything is written
    if a.out_csv:
        Path(a.out_csv).write_text(metrics.to_csv(rows, a.unit_column), encoding="utf-8")
    print(summary)
    return EXIT_OK


def _root(value: str) -> str:
    if not ROOT_RE.fullmatch(value or ""):
        raise ValueError("root must be 0x followed by 64 hexadecimal digits")
    return value.lower()


def cmd_verify_root(a):
    rows = toolkit.read_release(Path(a.dataset).read_text(encoding="utf-8"))
    a.root = _root(a.root)
    if a.k is not None:
        metrics.validate_release(rows, a.k)  # the root does not commit to k: the verifier checks it
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
    if not isinstance(row.get("count"), int) or isinstance(row.get("count"), bool):
        raise ValueError("count must be an integer")
    r = toolkit.Row(row["unit_id"], row["day"], row["category"], row["count"])
    anchored = a.root is not None
    root = _root(a.root if anchored else obj["root"])
    ok = toolkit.verify_row(r, [_root(x) for x in obj["proof"]], root)
    if not anchored:
        # without --root this only checks that the file is self-consistent, not that the row was published
        text = "CONSISTENT (not checked against an anchored root; pass --root from MetricsAnchor)" if ok else "MISMATCH"
    else:
        text = "MATCH" if ok else "MISMATCH"
    _out(a, {"root": root, "anchored": anchored, "match": ok}, text)
    return EXIT_OK if ok else EXIT_MISMATCH


def cmd_restricted_hash(a):
    print(policy.list_hash(policy.load_feed(a.list)))
    return EXIT_OK


def cmd_zone_hash(a):
    print(policy.zone_hash(Path(a.zone).read_text(encoding="utf-8")))
    return EXIT_OK


def cmd_check_onchain(a):
    """Compare a policy document with the values of its on-chain version (VPR-060)."""
    p = policy.load(a.policy)
    checks = {
        "contentHash": (p.content_hash(), a.content_hash.lower() if a.content_hash else None),
        "version": (p.doc["version"], a.version),
        "validitySeconds": (int(p.doc["valid_days"]) * 86400 if "valid_days" in p.doc else None, a.validity),
        "reasonCode": (p.doc.get("reason_code"), a.reason_code),
    }
    results = {k: {"document": d, "onchain": o, "match": o is None or d == o} for k, (d, o) in checks.items()}
    ok = all(r["match"] for r in results.values())
    _out(a, {"match": ok, "checks": results}, "\n".join(f"{k:<16} {'ok' if r['match'] else 'MISMATCH'}  document={r['document']} onchain={r['onchain']}" for k, r in results.items()))
    return EXIT_OK if ok else EXIT_MISMATCH


def _anchor(pairs: dict) -> tuple[dict, bool]:
    """Compare documents with on-chain content hashes. pairs: name -> (Policy, hash or None)."""
    out = {}
    for name, (p, h) in pairs.items():
        expected = _root(h) if h is not None else None
        out[name] = {"document": p.content_hash(), "onchain": expected, "match": expected is None or p.content_hash() == expected}
    return out, all(v["onchain"] is not None for v in out.values())


def _report(r: dict, ok: bool, anchored: bool, verdict: str) -> str:
    lines = [f"{k:<22} {'ok' if v else 'MISMATCH'}" for k, v in r["checks"].items()]
    state = lambda v: "unchecked" if v["onchain"] is None else ("ok" if v["match"] else "MISMATCH")  # noqa: E731
    lines += [f"contentHash {k:<10} {state(v)}  {v['document']}" for k, v in r["contentHash"].items()]
    lines += [f"note: {x}" for x in r["limits"]]
    if not anchored:
        lines.append("note: not checked against on-chain content hashes; pass them to bind the documents to the registry")
    return "\n".join(lines + [verdict if ok else "MISMATCH"])


def cmd_check_carryover(a):
    """ADR-0012: does an independent test of one version remain evidence for the version in force?"""
    tested, in_force = policy.load(a.tested), policy.load(a.in_force)
    r = policy.carry_over(tested, in_force)
    r["contentHash"], r["anchored"] = _anchor({"tested": (tested, a.tested_hash), "inForce": (in_force, a.in_force_hash)})
    ok = r["carriesOver"] and all(v["match"] for v in r["contentHash"].values())
    r["match"] = ok
    _out(a, r, _report(r, ok, r["anchored"], "CARRIES OVER"))
    return EXIT_OK if ok else EXIT_MISMATCH


def cmd_check_renewal(a):
    """GOVERNANCE reason code 2: a scheduled renewal keeps the rules digest of the version it renews."""
    previous, renewal = policy.load(a.previous), policy.load(a.renewal)
    r = policy.check_renewal(previous, renewal, a.reason_code)
    r["contentHash"], r["anchored"] = _anchor({"previous": (previous, a.previous_hash), "renewal": (renewal, a.renewal_hash)})
    ok = r["match"] and all(v["match"] for v in r["contentHash"].values())
    r["match"] = ok
    _out(a, r, _report(r, ok, r["anchored"], "OK" if r["renewalRuleApplies"] else "OK (not a renewal: reason code is not 2)"))
    return EXIT_OK if ok else EXIT_MISMATCH


def cmd_appeal_hash(a):
    doc = json.loads(Path(a.document).read_text(encoding="utf-8"))
    print(toolkit.appeal_document_hash(doc))
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="vpr", description="Verifiable Policy Registry tools (toolkit API v1)")
    sub = ap.add_subparsers(required=True)

    s = sub.add_parser("policy-hash", help="validate a policy and print its content hash and rules digest (and scope id, given the governor)")
    s.add_argument("policy")
    s.add_argument("--governor", help="governor address; the on-chain scope id is keccak256(abi.encode(governor, scope))")
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

    for name, help_text in (("restricted-hash", "print the commitment of a restricted list file (never publish the list)"),
                            ("list-hash", "print the commitment of a domain list (feed_hashes, restricted_list_hash)")):
        s = sub.add_parser(name, help=help_text)
        s.add_argument("list")
        s.set_defaults(func=cmd_restricted_hash)

    s = sub.add_parser("zone-hash", help="print keccak256 of a compiled zone (resolverConfigHash in the deployment attestation)")
    s.add_argument("zone")
    s.set_defaults(func=cmd_zone_hash)

    s = sub.add_parser("check-onchain", help="compare a policy document with the values of its on-chain version")
    s.add_argument("policy")
    s.add_argument("--content-hash")
    s.add_argument("--version", type=int)
    s.add_argument("--validity", type=int, help="validity in seconds passed to publishPolicy")
    s.add_argument("--reason-code", type=int)
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_check_onchain)

    s = sub.add_parser("check-carryover", help="check whether an independent test of one policy version remains evidence for the version in force (ADR-0012); does not check the attestation's validUntil or revocation")
    s.add_argument("tested", help="policy document of the version named in the test's policyVersion")
    s.add_argument("in_force", help="policy document of the version in force")
    s.add_argument("--tested-hash", help="on-chain content hash of the tested version")
    s.add_argument("--in-force-hash", help="on-chain content hash of the version in force")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_check_carryover)

    s = sub.add_parser("check-renewal", help="check that a version with reason code 2 keeps the rules digest of the version it renews (GOVERNANCE, ADR-0012)")
    s.add_argument("previous", help="policy document of the version being renewed")
    s.add_argument("renewal", help="policy document of the next version")
    s.add_argument("--reason-code", type=int, help="on-chain reason code of the next version; required if its document has none")
    s.add_argument("--previous-hash", help="on-chain content hash of the version being renewed")
    s.add_argument("--renewal-hash", help="on-chain content hash of the next version")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_check_renewal)

    s = sub.add_parser("appeal-hash", help="validate an appeal document (vpr-appeal/3) and print the hash to file")
    s.add_argument("document")
    s.set_defaults(func=cmd_appeal_hash)

    s = sub.add_parser("verify-root", help="recompute a published release's root")
    s.add_argument("dataset")
    s.add_argument("root")
    s.add_argument("--k", type=int, help="also check that every published count is at least k (the root does not commit to k)")
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
    except Exception as e:  # noqa: BLE001 - any other failure is invalid input, never a verification result
        print(f"error: invalid input ({type(e).__name__})", file=sys.stderr)
        code = EXIT_INVALID
    sys.exit(code)


if __name__ == "__main__":
    main()
