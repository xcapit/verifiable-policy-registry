# SPDX-License-Identifier: AGPL-3.0-only
"""Benchmark release construction and verification with synthetic rows.

Prints one JSON object. Measures wall-clock time on the machine it runs on; the numbers describe that
machine and this Python implementation only, not resolver or school-network performance.
"""

import json
import platform
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from vpr import toolkit  # noqa: E402

D = "2026-11-01"
CATS = ["malware", "phishing", "adult", "gambling", "violence"]


def synthetic_rows(n):
    return sorted(toolkit.Row(f"unit-{i // len(CATS):05d}", D, CATS[i % len(CATS)], 10 + i % 90) for i in range(n))


def timed(fn, repeat=3):
    best = float("inf")
    for _ in range(repeat):
        t0 = time.perf_counter()
        out = fn()
        best = min(best, time.perf_counter() - t0)
    return best, out


def main():
    results = []
    for n in (10, 100, 1_000, 10_000, 50_000):
        rows = synthetic_rows(n)
        t_root, root = timed(lambda: toolkit.release_root(rows))
        idx = n // 2
        proof = toolkit.row_proof(rows, idx)
        t_verify, ok = timed(lambda: toolkit.verify_row(rows[idx], proof, root), repeat=50)
        assert ok
        csv_bytes = len(toolkit.write_release(rows, "unit_id").encode())
        results.append({"rows": n, "rootSeconds": round(t_root, 4), "verifyRowMicroseconds": round(t_verify * 1e6, 1),
                        "proofLength": len(proof), "releaseCsvBytes": csv_bytes})
    print(json.dumps({"python": platform.python_version(), "machine": platform.machine(), "system": platform.system(),
                      "processor": platform.processor() or "unknown", "results": results}, indent=2))


if __name__ == "__main__":
    main()
