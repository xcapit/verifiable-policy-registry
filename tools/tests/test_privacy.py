"""Privacy regression tests: suppressed cells must not leak through any output, field or error."""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from vpr import metrics, toolkit

ROOT = Path(__file__).resolve().parents[2]
D = "2026-11-01"

# Synthetic release with two suppressed cells whose values and categories are distinctive.
EVENTS = [("u1", D, "malware")] * 25 + [("u1", D, "rare-category")] * 3 + [("u2", D, "adult")] * 10 + [("u2", D, "phishing")] * 9


def _rows():
    return toolkit.aggregate(EVENTS, 10)


def test_threshold_boundary():
    rows = _rows()
    cells = {(r.school_id, r.category): r.count for r in rows}
    assert cells[("u2", "adult")] == 10  # exactly k is published
    assert ("u2", "phishing") not in cells  # k - 1 is suppressed
    assert ("u1", "rare-category") not in cells


@pytest.mark.parametrize("render", [lambda rows: metrics.to_csv(rows), lambda rows: metrics.to_json(rows, 10), lambda rows: metrics.to_csv(rows, "unit_id")])
def test_outputs_contain_no_suppressed_cell_or_count(render):
    out = render(_rows())
    assert "rare-category" not in out
    assert "phishing" not in out
    assert "suppressed" not in out


def test_toolkit_aggregate_does_not_return_suppression_count():
    assert isinstance(toolkit.aggregate(EVENTS, 10), list)


def test_errors_do_not_echo_values():
    rows = [metrics.Row("u9", D, "secret-category", 3)]
    with pytest.raises(ValueError) as e:
        metrics.validate_release(rows, k=10)
    assert "secret-category" not in str(e.value) and "3" not in str(e.value) and "u9" not in str(e.value)


@pytest.mark.parametrize("count", ["-1", "0", "x", ""])
def test_malformed_counts_fail_safely(count):
    text = f"unit_id,day,category,count\nu1,{D},malware,{count}\n"
    with pytest.raises(ValueError):
        toolkit.release_root(toolkit.read_release(text))


def test_event_input_rejects_extra_fields():
    with pytest.raises(ValueError):
        metrics.read_events(f"unit_id,day,category,client_ip\nu1,{D},malware,10.0.0.1\n")


def test_ordering_does_not_depend_on_input_order():
    import random

    shuffled = list(EVENTS)
    random.Random(7).shuffle(shuffled)
    assert metrics.to_csv(toolkit.aggregate(shuffled, 10)) == metrics.to_csv(_rows())


def test_demo_outputs_contain_no_suppressed_cells(tmp_path):
    subprocess.run(
        [sys.executable, str(ROOT / "examples" / "e2e" / "prepare.py"), "--policy", str(ROOT / "policies" / "example-primary.yaml"),
         "--events", str(ROOT / "examples" / "events.csv"), "--day", D, "--k", "10", "--out-dir", str(tmp_path)],
        check=True, capture_output=True, text=True,
        env={**__import__("os").environ, "PYTHONPATH": str(ROOT / "tools")},
    )
    # suppressed cells in examples/events.csv on 2026-11-01: giga-0002 (malware, phishing, adult: 3 each), giga-0003 phishing (3)
    for f in tmp_path.iterdir():
        text = f.read_text(encoding="utf-8")
        assert "giga-0002" not in text, f.name
        assert '"count": 3' not in text and ",3\n" not in text, f.name
        assert "suppressed" not in text.lower(), f.name
