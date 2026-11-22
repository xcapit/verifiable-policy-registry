#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Resolver check (VPR-055): builds the pinned Unbound image in deploy/unbound/test, then runs
# examples/resolver/check.py, which serves zones compiled from the example policy and queries them
# with dig. Requirements: Docker, Python 3.10+ and `pip install -e tools`.
# Outputs go to $RESOLVER_OUT (default: a new temporary directory); nothing is written elsewhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${RESOLVER_OUT:-$(mktemp -d)}"
IMAGE="${RESOLVER_IMAGE:-vpr-unbound-test:local}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$ROOT"

command -v docker >/dev/null || { echo "error: Docker is required" >&2; exit 2; }
python -c "import vpr" 2>/dev/null || { echo "error: run 'pip install -e tools' first" >&2; exit 2; }

echo "== build the pinned resolver image ($IMAGE)"
docker build -q -t "$IMAGE" deploy/unbound/test

echo; echo "== serve the compiled zones and query them"
python examples/resolver/check.py --image "$IMAGE" --out "$OUT"
