#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# End-to-end demonstrator with synthetic data:
#   policy -> zone -> zone evaluation -> aggregation with suppression -> Merkle root -> local chain
#   -> chain state read-back -> row proofs (accepted / tampered / wrong day) -> appeal -> expiry
#   -> explicit ZK boundary -> evidence manifest.
# Requirements: Node.js 20+, Python 3.10+, `npm ci` in contracts/ and `pip install -e tools/`.
# Outputs go to $E2E_OUT (default: a new temporary directory); nothing is written elsewhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${E2E_OUT:-$(mktemp -d)}"
DAY="${E2E_DAY:-2026-11-01}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"   # absolute: the on-chain stage runs from contracts/
cd "$ROOT"

command -v node >/dev/null || { echo "error: Node.js 20+ is required" >&2; exit 2; }
command -v vpr >/dev/null || { echo "error: run 'pip install -e tools' first" >&2; exit 2; }
[ -d contracts/node_modules ] || { echo "error: run 'npm ci' in contracts/ first" >&2; exit 2; }

echo "== off-chain: policy hash, zone compilation and evaluation, releases (k = 10)"
python examples/e2e/prepare.py --policy policies/example-primary.yaml --feeds-dir examples/feeds \
  --events examples/events.csv --service-events examples/public-service/events.csv \
  --day "$DAY" --k 10 --out-dir "$OUT"

echo; echo "== off-chain: first lines of the compiled zone"
head -n 2 "$OUT/policy.rpz"

echo; echo "== off-chain: anyone can recompute the published roots"
vpr verify-root "$OUT/school-release.csv" "$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["root"])' "$OUT/e2e.json")"
vpr verify-root "$OUT/service-release.csv" "$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["service"]["root"])' "$OUT/e2e.json")"
if vpr verify-root "$OUT/school-release.csv" "0x$(printf '1%.0s' {1..64})" >/dev/null; then
  echo "error: a wrong root was accepted" >&2; exit 1
fi
echo "ok    a wrong root is rejected (exit code 1)"

echo; echo "== on-chain: deploy, govern, publish, anchor, verify, expire (Hardhat in-process network)"
cd contracts
E2E_INPUT="$OUT/e2e.json" E2E_OFFCHAIN="$OUT/offchain-evidence.json" E2E_MANIFEST="$OUT/evidence-manifest.json" \
  E2E_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
  npx hardhat run scripts/e2e.js

echo; echo "Evidence manifest: $OUT/evidence-manifest.json"
echo "Teardown: nothing to stop (the chain runs in-process); remove $OUT when done."
