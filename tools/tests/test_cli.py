"""CLI behaviour: JSON output and exit codes (0 ok, 1 mismatch, 2 invalid input)."""

import json
from pathlib import Path

import pytest

from vpr import cli

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / "examples" / "public-service" / "events.csv"


def run(capsys, *args):
    with pytest.raises(SystemExit) as e:
        cli.main(list(args))
    out = capsys.readouterr()
    return e.value.code, out.out, out.err


def test_aggregate_prove_and_verify_roundtrip(tmp_path, capsys):
    csv_path = tmp_path / "r.csv"
    code, out, _ = run(capsys, "aggregate", str(SERVICE), "--k", "10", "--unit-column", "unit_id", "--out-csv", str(csv_path))
    assert code == 0
    root = json.loads(out)["root"]
    code, out, _ = run(capsys, "verify-root", str(csv_path), root, "--json")
    assert code == 0 and json.loads(out)["match"] is True
    code, out, _ = run(capsys, "prove-row", str(csv_path), "--index", "0")
    assert code == 0
    proof_path = tmp_path / "p.json"
    proof_path.write_text(out)
    code, out, _ = run(capsys, "verify-row", str(proof_path), "--json")
    assert code == 0 and json.loads(out)["match"] is True


def test_mismatch_exits_1(tmp_path, capsys):
    csv_path = tmp_path / "r.csv"
    run(capsys, "aggregate", str(SERVICE), "--k", "10", "--unit-column", "unit_id", "--out-csv", str(csv_path))
    code, _, _ = run(capsys, "verify-root", str(csv_path), "0x" + "11" * 32)
    assert code == 1
    code, out, _ = run(capsys, "prove-row", str(csv_path), "--index", "0")
    p = json.loads(out)
    p["row"]["count"] += 1
    (tmp_path / "bad.json").write_text(json.dumps(p))
    code, _, _ = run(capsys, "verify-row", str(tmp_path / "bad.json"))
    assert code == 1


@pytest.mark.parametrize(
    "args",
    [
        ["aggregate", str(ROOT / "examples" / "events.csv")],  # several days without --day
        ["verify-root", "/nonexistent.csv", "0x00"],
        ["policy-hash", str(ROOT / "README.md")],
    ],
)
def test_invalid_input_exits_2_without_traceback(args, capsys):
    code, _, err = run(capsys, *args)
    assert code == 2
    assert err.startswith("error:") and "Traceback" not in err


def test_evaluate_json(tmp_path, capsys):
    zone = tmp_path / "z.rpz"
    run(capsys, "compile-rpz", str(ROOT / "policies" / "example-primary.yaml"), "--feeds-dir", str(ROOT / "examples" / "feeds"), "--out", str(zone))
    code, out, _ = run(capsys, "evaluate", str(zone), "wikipedia.org", "bad-malware.example", "--json")
    assert code == 0
    actions = [r["action"] for r in json.loads(out)["results"]]
    assert actions == ["passthru", "nxdomain"]
