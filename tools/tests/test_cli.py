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


# ADR-0012: carry-over of independent tests and the renewal rule (check-carryover, check-renewal).
EXAMPLE = ROOT / "policies" / "example-primary.yaml"


def version(tmp_path, n, reason=2, valid_days=30, change=None, drop=()):
    from vpr import policy

    doc = policy.load(EXAMPLE).doc
    doc.update(version=n, reason_code=reason, valid_days=valid_days)
    for k in drop:
        doc.pop(k)
    if change:
        change(doc)
    path = tmp_path / f"v{n}.json"
    path.write_text(json.dumps(doc))
    return path, policy.validate(doc).content_hash()


def add_block(doc):
    doc["local_blocks"].append({"domain": "new-block.example", "reason": "rule change"})


def test_carryover_across_a_renewal(tmp_path, capsys):
    v1, h1 = version(tmp_path, 1, reason=1, valid_days=90)
    v2, h2 = version(tmp_path, 2)
    code, out, _ = run(capsys, "check-carryover", str(v1), str(v2), "--tested-hash", h1, "--in-force-hash", h2, "--json")
    r = json.loads(out)
    assert code == 0 and r["carriesOver"] and r["anchored"] and r["limits"] == []


def test_carryover_refused_after_a_rule_change(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2, reason=6, change=add_block)
    code, out, _ = run(capsys, "check-carryover", str(v1), str(v2), "--json")
    r = json.loads(out)
    assert code == 1 and r["checks"]["sameRulesDigest"] is False and r["anchored"] is False


def test_carryover_refused_from_a_later_version(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2)
    code, out, _ = run(capsys, "check-carryover", str(v2), str(v1), "--json")
    assert code == 1 and json.loads(out)["checks"]["testedNotLater"] is False


def test_carryover_refused_on_a_content_hash_mismatch(tmp_path, capsys):
    v1, h1 = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2)
    code, out, _ = run(capsys, "check-carryover", str(v1), str(v2), "--tested-hash", h1, "--in-force-hash", "0x" + "11" * 32, "--json")
    r = json.loads(out)
    assert code == 1 and r["carriesOver"] is True and r["contentHash"]["inForce"]["match"] is False


def test_carryover_flags_a_digest_without_feed_hashes(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1, drop=("feed_hashes",))
    v2, _ = version(tmp_path, 2, drop=("feed_hashes",))
    code, out, _ = run(capsys, "check-carryover", str(v1), str(v2), "--json")
    r = json.loads(out)
    assert code == 0 and len(r["limits"]) == 1 and "feed" in r["limits"][0]


def test_renewal_rule(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2)
    code, out, _ = run(capsys, "check-renewal", str(v1), str(v2), "--json")
    assert code == 0 and json.loads(out)["renewalRuleApplies"] is True


def test_rule_change_labelled_as_renewal_exits_1(tmp_path, capsys):
    # the abuse case of ADR-0012: a governor labels a change of rules as a scheduled renewal
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2, change=add_block)
    code, out, _ = run(capsys, "check-renewal", str(v1), str(v2), "--json")
    assert code == 1 and json.loads(out)["checks"]["sameRulesDigest"] is False


def test_renewal_reason_code_must_agree_with_chain(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2, reason=6, change=add_block)
    # the document says correction, the chain says renewal: a mismatch, and the renewal rule is applied
    code, out, _ = run(capsys, "check-renewal", str(v1), str(v2), "--reason-code", "2", "--json")
    r = json.loads(out)
    assert code == 1 and r["checks"]["reasonCodeConsistent"] is False and r["checks"]["sameRulesDigest"] is False


def test_renewal_must_be_the_next_version(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v3, _ = version(tmp_path, 3)
    code, out, _ = run(capsys, "check-renewal", str(v1), str(v3), "--json")
    assert code == 1 and json.loads(out)["checks"]["nextVersion"] is False


def test_non_renewal_passes_without_the_digest_rule(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2, reason=6, change=add_block)
    code, out, _ = run(capsys, "check-renewal", str(v1), str(v2), "--json")
    r = json.loads(out)
    assert code == 0 and r["renewalRuleApplies"] is False and "sameRulesDigest" not in r["checks"]


def test_renewal_with_unknown_reason_code_exits_2(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    v2, _ = version(tmp_path, 2, drop=("reason_code",))
    code, _, err = run(capsys, "check-renewal", str(v1), str(v2))
    assert code == 2 and "reason code" in err


def test_carryover_bad_hash_exits_2(tmp_path, capsys):
    v1, _ = version(tmp_path, 1, reason=1)
    code, _, err = run(capsys, "check-carryover", str(v1), str(v1), "--tested-hash", "0x12")
    assert code == 2 and err.startswith("error:")
