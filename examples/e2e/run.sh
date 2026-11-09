#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# End-to-end demo: policy -> registry -> RPZ -> aggregation -> anchored root -> row verification.
# Requirements: Node.js 20+, Python 3.10+, `npm ci` in contracts/ and `pip install -e tools/`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${E2E_OUT:-$(mktemp -d)}"
DAY="${E2E_DAY:-2026-11-01}"
cd "$ROOT"

echo "== off-chain: hash policy, aggregate ${DAY} with k = 10"
python examples/e2e/prepare.py --policy policies/example-primary.yaml --events examples/events.csv \
  --day "$DAY" --k 10 --out-dir "$OUT"

echo; echo "== off-chain: compile the RPZ zone (first lines)"
vpr compile-rpz policies/example-primary.yaml --feeds-dir examples/feeds --block-page block.example.org \
  --out "$OUT/policy.rpz" > /dev/null
head -n 2 "$OUT/policy.rpz"

echo; echo "== off-chain: anyone can recompute the published root"
vpr verify-root "$OUT/dataset.csv" "$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["root"])' "$OUT/e2e.json")"

echo; echo "== on-chain: deploy, publish, anchor, verify (Hardhat in-process network)"
cd contracts
E2E_INPUT="$OUT/e2e.json" npx hardhat run scripts/e2e.js
