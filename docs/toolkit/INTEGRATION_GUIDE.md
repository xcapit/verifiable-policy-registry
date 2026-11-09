# Verification toolkit: integration guide

*CC BY 4.0 · Toolkit API version 1 · Code AGPL-3.0-only; schemas CC0-1.0.*

The toolkit lets any publisher of aggregate public-interest figures commit to a daily release on an EVM chain and lets anyone verify it, without exposing small counts. It has no school- or filtering-specific logic. Content filtering for schools is one use case; [public-service interruptions](../../examples/public-service/README.md) is another, verified by the same code and the same contract.

## What you get

| Piece | Status | Where |
| --- | --- | --- |
| Python library (`vpr.toolkit`) | Implemented | [`tools/vpr/toolkit.py`](../../tools/vpr/toolkit.py) |
| CLI (`vpr aggregate`, `verify-root`, `prove-row`, `verify-row`) | Implemented | [`tools/vpr/cli.py`](../../tools/vpr/cli.py) |
| On-chain anchor and row verifier (`MetricsAnchor`) | Implemented, not audited | [`contracts/src/MetricsAnchor.sol`](../../contracts/src/MetricsAnchor.sol) |
| Release JSON schema | Implemented | [`schemas/dataset.schema.json`](../../schemas/dataset.schema.json) |
| Encoding specification | Implemented | [Cryptographic evidence §3](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md) |
| ZK proof of aggregation, `vpr verify-proof` | Designed | Same document, §5–§6; roadmap M4 |
| Deployment manifest format | Planned | VPR-049 |

## Five-minute integration

1. **Emit events** as a CSV with exactly three columns, `unit_id,day,category`. One row per event, UTC dates, no other fields. The reader rejects extra columns.
2. **Aggregate** one day with a threshold:
   ```bash
   vpr aggregate events.csv --day 2026-11-03 --k 10 --unit-column unit_id --out-csv release.csv > summary.json
   ```
   `summary.json` contains `format`, `k`, `root` and the published rows. Suppressed cells and their number are not reported.
3. **Anchor** the root. In the registry, the governor of your scope calls `createScope` and appoints a publisher with `MetricsAnchor.setPublisher`; the publisher then calls `commitRoot(scopeId, dayNumber, root, datasetUri)` once per day. `dayNumber` is the number of days since 1970-01-01 (`vpr.toolkit.day_number`).
4. **Publish** `release.csv` at `datasetUri`, mirrored on more than one host.
5. **Verify**, as anyone:
   ```bash
   vpr verify-root release.csv <root from MetricsAnchor.getCommitment>   # whole release
   vpr prove-row release.csv --index 3 > proof.json                        # one row
   vpr verify-row proof.json --root <anchored root>
   ```
   or on-chain, with `MetricsAnchor.verifyRow(scopeId, day, unitId, category, count, proof)`.

## Python API (v1)

```python
from vpr import toolkit

rows = toolkit.aggregate(events, k=10)          # events: iterable of (unit_id, day, category)
root = toolkit.release_root(rows)               # validates: one day, unique cells, counts >= 1
proof = toolkit.row_proof(rows, 0)
assert toolkit.verify_row(rows[0], proof, root)
csv_text = toolkit.write_release(rows, "unit_id")
rows_again = toolkit.read_release(csv_text)     # accepts unit_id or school_id as the unit column
h = toolkit.document_hash({"any": "json"})      # canonical JSON + keccak256 (policy and appeal documents)
```

Errors are raised as `ValueError` and never contain dataset values.

## CLI conventions

- Exit code `0` means success, `1` a verification mismatch, and `2` invalid input or usage.
- `--json` prints one JSON object on stdout.
- Errors are printed to stderr as `error: …`, never with a traceback, and never echo dataset values.

## Compatibility policy

- The toolkit API, the CLI commands and their JSON fields follow semantic versioning of the `vpr-tools` package. Removing or changing them is a major version change.
- The **dataset format** (`vpr-dataset/2`) and the leaf and node encoding are versioned independently. Any change to the encoding creates a new format version, and a matching contract function, with an ADR and new shared test vectors. A published root always remains verifiable with the tools of its format version.
- Contracts are not upgradeable. A new contract version is a new deployment; old roots stay readable at the old address.

## Limits you inherit

- The root proves that the release was not changed after anchoring. It does **not** prove that the events were complete or truthful ([cryptographic evidence §12](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md)).
- The threshold counts events, not people. Decide your release policy with the [privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md).
- No contract has been audited.
