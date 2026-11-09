"""Regression tests for findings of the second (security and privacy) review of v0.3."""

import copy
import json
import os
import stat
from pathlib import Path

import pytest

from vpr import cli, merkle, metrics, policy, toolkit

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "policies" / "example-primary.yaml"
FEEDS = ROOT / "examples" / "feeds"
D = "2026-11-01"


def _feeds():
    return {f.stem: policy.load_feed(f) for f in FEEDS.glob("*.txt")}


def _with_restricted(domains, **changes):
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc["restricted_list_hash"] = policy.restricted_list_hash(domains)
    doc.update(changes)
    return policy.validate(doc)


def run(capsys, *args):
    with pytest.raises(SystemExit) as e:
        cli.main(list(args))
    out = capsys.readouterr()
    return e.value.code, out.out, out.err


# Compiler -------------------------------------------------------------------------------------------

def test_exception_cannot_cancel_restricted_entry_and_error_does_not_name_it():
    p = _with_restricted(["hidden-one.example", "wikipedia.org"])
    with pytest.raises(policy.PolicyError) as e:
        policy.compile_rpz(p, _feeds(), restricted=["hidden-one.example", "wikipedia.org"], serial=1)
    assert "wikipedia" not in str(e.value) and "hidden" not in str(e.value)


def test_exception_on_parent_of_restricted_entry_is_rejected():
    p = _with_restricted(["sub.wikipedia.org"])
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(p, _feeds(), restricted=["sub.wikipedia.org"], serial=1)


def test_empty_feed_fails_closed():
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(policy.load(EXAMPLE), dict(_feeds(), malware=[]), serial=1)


def test_block_page_is_validated():
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(policy.load(EXAMPLE), _feeds(), block_page="block.example.org\nevil.example CNAME rpz-passthru.")


def test_zone_is_deterministic():
    p = policy.load(EXAMPLE)
    assert policy.compile_rpz(p, _feeds()) == policy.compile_rpz(p, _feeds())


def test_restricted_list_errors_do_not_echo_entries(tmp_path):
    f = tmp_path / "r.txt"
    f.write_text("https://secret.example/x\n")
    with pytest.raises(policy.PolicyError) as e:
        policy.load_feed(f)
    assert "secret" not in str(e.value)


# Policy loading -------------------------------------------------------------------------------------

def test_duplicate_yaml_keys_are_rejected(tmp_path):
    f = tmp_path / "p.yaml"
    f.write_text(EXAMPLE.read_text() + "\nlocal_blocks: []\n")
    with pytest.raises(policy.PolicyError):
        policy.load(f)


@pytest.mark.parametrize(
    "change",
    [
        {"scope": "giga:XX:primary\n"},
        {"categories": ["malware\n"]},
        {"local_blocks": [{"domain": "x.example", "reason": True}]},
        {"local_blocks": [{"domain": True, "reason": "x"}]},
    ],
)
def test_strict_types_and_full_matches(change):
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc.update(change)
    with pytest.raises(policy.PolicyError):
        policy.validate(doc)


# Zone evaluation --------------------------------------------------------------------------------------

@pytest.mark.parametrize(
    "zone,action",
    [
        ("bad.example 300 IN CNAME .\n", "nxdomain"),
        ("BAD.example. CNAME .\n", "nxdomain"),
        ("bad.example CNAME *.\n", "nodata"),
        ("bad.example CNAME rpz-drop.\n", "drop"),
        ("bad.example CNAME RPZ-PASSTHRU.\n", "passthru"),
    ],
)
def test_evaluator_understands_common_rpz_forms(zone, action):
    assert policy.evaluate_zone(zone, "bad.example")["action"] == action


def test_evaluator_fails_closed_on_unknown_records():
    with pytest.raises(policy.PolicyError):
        policy.evaluate_zone("bad.example A 192.0.2.1\n", "bad.example")


# Aggregation boundary -------------------------------------------------------------------------------

@pytest.mark.parametrize(
    "header,row",
    [
        ("unit_id,day,category", f"s1,{D},facebook.com"),       # a domain as a category
        ("unit_id,day,category", f"192.0.2.10,{D},malware"),    # an address as a unit
        ("unit_id,day,category", f"s1,{D},malware,extra"),      # extra field
        ("unit_id,day,category", "s1,2026-11-01"),              # missing field
        ("unit_id,day,category", "s1,20261101,malware"),        # non-strict date
    ],
)
def test_events_outside_the_boundary_are_rejected_without_echo(header, row):
    with pytest.raises(ValueError) as e:
        metrics.read_events(f"{header}\n{row}\n")
    for secret in ("facebook", "192.0.2.10", "extra"):
        assert secret not in str(e.value)


@pytest.mark.parametrize("count", ["+5", "1_0", " 5", "5.0"])
def test_release_counts_are_strict_decimals(count):
    with pytest.raises(ValueError):
        toolkit.read_release(f"unit_id,day,category,count\nu1,{D},malware,{count}\n")


def test_proof_elements_must_be_32_bytes():
    rows = toolkit.aggregate([("u1", D, "malware")] * 10 + [("u2", D, "malware")] * 10, 10)
    root = toolkit.release_root(rows)
    assert not merkle.verify(rows[0].leaf(), [b"\x00" * 31], bytes.fromhex(root[2:]))


def test_canonical_json_rejects_floats_and_nan():
    for bad in ({"a": 1.0}, {"a": float("nan")}):
        with pytest.raises(ValueError):
            toolkit.canonical_json(bad)


# CLI --------------------------------------------------------------------------------------------------

def _release(tmp_path, capsys):
    csv_path = tmp_path / "r.csv"
    code, out, _ = run(capsys, "aggregate", str(ROOT / "examples" / "public-service" / "events.csv"), "--k", "10",
                       "--unit-column", "unit_id", "--out-csv", str(csv_path))
    assert code == 0
    return csv_path, json.loads(out)["root"]


def test_verify_row_without_root_is_not_reported_as_anchored(tmp_path, capsys):
    csv_path, root = _release(tmp_path, capsys)
    _, out, _ = run(capsys, "prove-row", str(csv_path), "--index", "0")
    (tmp_path / "p.json").write_text(out)
    code, out, _ = run(capsys, "verify-row", str(tmp_path / "p.json"), "--json")
    assert code == 0 and json.loads(out)["anchored"] is False
    code, out, _ = run(capsys, "verify-row", str(tmp_path / "p.json"), "--root", root, "--json")
    assert code == 0 and json.loads(out)["anchored"] is True


def test_root_without_prefix_is_invalid_input(tmp_path, capsys):
    csv_path, root = _release(tmp_path, capsys)
    code, _, _ = run(capsys, "verify-root", str(csv_path), root[2:])
    assert code == 2


def test_verify_root_can_enforce_k(tmp_path, capsys):
    p = tmp_path / "small.csv"
    p.write_text(f"unit_id,day,category,count\nu1,{D},malware,3\n")
    root = toolkit.release_root(toolkit.read_release(p.read_text()))
    assert run(capsys, "verify-root", str(p), root)[0] == 0      # the root does not commit to k
    assert run(capsys, "verify-root", str(p), root, "--k", "10")[0] == 2


def test_unexpected_errors_exit_2_without_traceback(tmp_path, capsys):
    bad = tmp_path / "p.json"
    bad.write_text('{"row": {"unit_id": "u", "day": "2026-11-01", "category": "c", "count": null}, "proof": [], "root": "0x' + "00" * 32 + '"}')
    code, _, err = run(capsys, "verify-row", str(bad))
    assert code == 2 and "Traceback" not in err


def test_zone_file_is_written_owner_only(tmp_path, capsys):
    out = tmp_path / "z.rpz"
    run(capsys, "compile-rpz", str(EXAMPLE), "--feeds-dir", str(FEEDS), "--out", str(out))
    assert stat.S_IMODE(os.stat(out).st_mode) == 0o600


# Pre-audit hardening ---------------------------------------------------------------------------------

def test_scope_id_matches_the_contract_vector():
    # Shared vector with contracts/test/VerifiablePolicyRegistry.test.js (Hardhat account #0).
    from vpr.hashing import scope_id

    assert scope_id("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", "giga:XX:primary") == (
        "0x8ed60dd6aab12c6e2f1a8fce4a8e3417f75ce71c0f10705b20241392abef33fb"
    )
    assert policy.load(EXAMPLE).scope_id("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266").startswith("0x8ed60dd6")


def test_feed_contents_are_bound_by_the_policy():
    p = policy.load(EXAMPLE)
    feeds = _feeds()
    policy.compile_rpz(p, feeds, serial=1)  # declared hashes match the example feeds
    tampered = dict(feeds, malware=feeds["malware"] + ["new-domain.example"])
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(p, tampered, serial=1)


def test_feed_hashes_must_cover_exactly_the_categories():
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc["feed_hashes"].pop("adult")
    with pytest.raises(policy.PolicyError):
        policy.validate(doc)


def test_appeal_format_3_requires_a_nonce_and_known_fields():
    good = {"format": "vpr-appeal/3", "scope": "giga:XX:primary", "domain": "educational-site.example",
            "request": "unblock", "reason": "Used in class", "nonce": "0x" + "ab" * 32}
    assert toolkit.appeal_document_hash(good).startswith("0x")
    for change in ({"nonce": "0x12"}, {"format": "vpr-appeal/2"}, {"request": "delete"}, {"reason": "x" * 281},
                   {"student": "name"}):
        bad = dict(good, **change)
        with pytest.raises(ValueError):
            toolkit.appeal_document_hash(bad)


def test_check_onchain_detects_mismatches(capsys):
    p = policy.load(EXAMPLE)
    ok_args = ["check-onchain", str(EXAMPLE), "--content-hash", p.content_hash(), "--version", "1",
               "--validity", str(int(p.doc["valid_days"]) * 86400), "--reason-code", "1"]
    assert run(capsys, *ok_args)[0] == 0
    assert run(capsys, "check-onchain", str(EXAMPLE), "--validity", "86400")[0] == 1
    assert run(capsys, "check-onchain", str(EXAMPLE), "--version", "2")[0] == 1


def test_zone_hash_is_stable(tmp_path, capsys):
    out = tmp_path / "z.rpz"
    run(capsys, "compile-rpz", str(EXAMPLE), "--feeds-dir", str(FEEDS), "--out", str(out))
    code, h1, _ = run(capsys, "zone-hash", str(out))
    assert code == 0 and h1.strip() == policy.zone_hash(out.read_text())
