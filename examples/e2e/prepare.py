# SPDX-License-Identifier: AGPL-3.0-only
"""Off-chain half of the end-to-end demonstrator (synthetic data only).

1. Validates and hashes the example policy; compiles its RPZ zone (fails closed).
2. Evaluates synthetic allowed and blocked domains against the compiled zone. This is a zone
   evaluation of the artefact a resolver would load, not DNS resolution.
3. Aggregates one day of synthetic school events and one day of synthetic public-service events with
   small-cell suppression, and builds the release roots and row proofs.
4. Writes `e2e.json` (input for contracts/scripts/e2e.js) and `offchain-evidence.json`.

No raw events, suppressed cells or suppression counts are written to any output.
"""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path

from vpr import __version__, metrics, policy, toolkit
from vpr.hashing import keccak256, to_hex

ALLOWED_PROBES = ["wikipedia.org", "en.wikipedia.org", "khanacademy.org", "neutral-site.example"]
BLOCKED_PROBES = ["bad-malware.example", "cdn.bad-malware.example", "casino-example.example"]


def release(events_path: Path, day: str | None, k: int) -> list[metrics.Row]:
    events = metrics.read_events(events_path.read_text(encoding="utf-8"))
    if day:
        events = [e for e in events if e[1] == day]
    return toolkit.aggregate(events, k)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--feeds-dir", default=None)
    ap.add_argument("--events", required=True)
    ap.add_argument("--service-events", default=None)
    ap.add_argument("--day", required=True, help="ISO date to aggregate, e.g. 2026-11-01")
    ap.add_argument("--k", type=int, default=metrics.DEFAULT_K)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()

    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    stages = []

    p = policy.load(a.policy)
    stages.append({"stage": "policy-validate-and-hash", "status": "passed", "contentHash": p.content_hash()})

    probes = []
    if a.feeds_dir:
        feeds = {f.stem: policy.load_feed(f) for f in Path(a.feeds_dir).glob("*.txt")}
        zone = policy.compile_rpz(p, feeds, block_page="block.example.org", serial=1)
        (out / "policy.rpz").write_text(zone, encoding="utf-8")
        for d in ALLOWED_PROBES + BLOCKED_PROBES:
            r = policy.evaluate_zone(zone, d)
            expected_blocked = d in BLOCKED_PROBES
            r["expectedBlocked"] = expected_blocked
            r["ok"] = (r["action"] in ("redirect", "nxdomain")) == expected_blocked
            probes.append(r)
        ok = all(r["ok"] for r in probes)
        stages.append({"stage": "zone-compile-and-evaluate", "status": "passed" if ok else "failed",
                       "note": "zone evaluation of the compiled RPZ, not DNS resolution", "probes": probes})
        if not ok:
            raise SystemExit("zone evaluation did not match expectations")

    rows = release(Path(a.events), a.day, a.k)
    if not rows:
        raise SystemExit(f"no cell reaches k={a.k} on {a.day}")
    (out / "school-release.csv").write_text(metrics.to_csv(rows, "school_id"), encoding="utf-8")
    first = rows[0]
    stages.append({"stage": "aggregate-suppress-commit (school)", "status": "passed", "publishedRows": len(rows)})

    service = None
    if a.service_events:
        srows = release(Path(a.service_events), None, a.k)
        (out / "service-release.csv").write_text(metrics.to_csv(srows, "unit_id"), encoding="utf-8")
        s0 = srows[0]
        service = {
            "scope": "public-service:XX:water",
            "scopeId": to_hex(keccak256(b"public-service:XX:water")),
            "day": s0.day,
            "dayNumber": toolkit.day_number(s0.day),
            "root": toolkit.release_root(srows),
            "row": {"unit_id": s0.school_id, "day": s0.day, "category": s0.category, "count": s0.count},
            "proof": toolkit.row_proof(srows, 0),
        }
        stages.append({"stage": "aggregate-suppress-commit (public service)", "status": "passed", "publishedRows": len(srows)})

    appeal_doc = {"format": "vpr-appeal/2", "scope": p.scope, "domain": "educational-site.example",
                  "request": "unblock", "reason": "Used in the science curriculum"}
    tampered_doc = dict(p.doc, local_blocks=p.doc["local_blocks"] + [{"domain": "added-later.example", "reason": "not approved"}])

    data = {
        "scope": p.scope,
        "scopeId": p.scope_id(),
        "policyVersion": p.doc["version"],
        "contentHash": p.content_hash(),
        "tamperedDocumentHash": toolkit.document_hash(tampered_doc),
        "policyUri": "ipfs://example-policy",
        "validDays": int(p.doc.get("valid_days", 90)),
        "reasonCode": int(p.doc.get("reason_code", 1)),
        "appealDocumentHash": toolkit.document_hash(appeal_doc),
        "day": a.day,
        "dayNumber": metrics.day_number(a.day),
        "k": a.k,
        "root": toolkit.release_root(rows),
        "datasetUri": "ipfs://example-dataset",
        "row": {"school_id": first.school_id, "day": first.day, "category": first.category, "count": first.count},
        "proof": toolkit.row_proof(rows, 0),
        "tamperedRow": {"school_id": first.school_id, "day": first.day, "category": first.category, "count": first.count + 1},
        "service": service,
    }
    (out / "e2e.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    (out / "offchain-evidence.json").write_text(json.dumps({
        "toolkitApi": toolkit.API_VERSION,
        "vprToolsVersion": __version__,
        "datasetFormat": toolkit.DATASET_FORMAT,
        "python": platform.python_version(),
        "stages": stages,
    }, indent=2), encoding="utf-8")

    print(f"policy  {p.scope} v{p.doc['version']}  contentHash {data['contentHash']}")
    for r in probes:
        print(f"zone    {r['action']:<9} {r['domain']}")
    print(f"school  {a.day} (day {data['dayNumber']})  published rows {len(rows)}  k {a.k}  root {data['root']}")
    if service:
        print(f"service {service['day']}  root {service['root']}")


if __name__ == "__main__":
    main()
