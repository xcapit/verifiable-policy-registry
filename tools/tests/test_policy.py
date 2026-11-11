import copy
from pathlib import Path

import pytest

from vpr import policy
from vpr.hashing import keccak256

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "policies" / "example-primary.yaml"
FEEDS = ROOT / "examples" / "feeds"


def test_keccak_known_vector():
    # keccak256("") as used by Ethereum
    assert keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"


def test_example_policy_loads_and_hash_is_stable():
    p1 = policy.load(EXAMPLE)
    p2 = policy.load(EXAMPLE)
    assert p1.content_hash() == p2.content_hash()
    assert p1.content_hash().startswith("0x") and len(p1.content_hash()) == 66


def test_hash_changes_when_policy_changes():
    p = policy.load(EXAMPLE)
    doc = copy.deepcopy(p.doc)
    doc["local_blocks"].append({"domain": "new-block.example", "reason": "test"})
    assert policy.validate(doc).content_hash() != p.content_hash()


def test_every_entry_needs_a_reason():
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc["local_blocks"].append({"domain": "no-reason.example", "reason": "  "})
    with pytest.raises(policy.PolicyError):
        policy.validate(doc)


def test_domain_cannot_be_blocked_and_excepted():
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc["local_blocks"].append({"domain": "wikipedia.org", "reason": "test"})
    with pytest.raises(policy.PolicyError):
        policy.validate(doc)


def test_rpz_exceptions_win_over_feeds():
    p = policy.load(EXAMPLE)
    zone = policy.compile_rpz(p, _feeds(), block_page="block.example.org", serial=1)
    assert "wikipedia.org CNAME rpz-passthru." in zone
    assert "wikipedia.org CNAME block.example.org." not in zone
    assert "bad-malware.example CNAME block.example.org." in zone
    assert "casino-example.example CNAME block.example.org." in zone


def _feeds():
    return {f.stem: policy.load_feed(f) for f in FEEDS.glob("*.txt")}


def _with_restricted(domains):
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc["restricted_list_hash"] = policy.restricted_list_hash(domains)
    return policy.validate(doc)


def test_restricted_entries_are_not_labelled():
    p = _with_restricted(["hidden-one.example"])
    zone = policy.compile_rpz(p, _feeds(), restricted=["hidden-one.example"], serial=1)
    line = next(l for l in zone.splitlines() if l.startswith("hidden-one.example"))
    assert ";" not in line  # no source label: the zone must not reveal which entries come from the restricted list


def test_restricted_list_hash_is_order_independent():
    a = policy.restricted_list_hash(["b.example", "a.example"])
    b = policy.restricted_list_hash(["a.example", "b.example", "a.example"])
    assert a == b


def test_compiler_fails_closed_on_missing_feed():
    p = policy.load(EXAMPLE)
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(p, {"malware": ["bad-malware.example"]}, serial=1)
    # explicit opt-out for testing only
    assert policy.compile_rpz(p, {}, serial=1, allow_missing_feeds=True)


def test_restricted_list_must_match_the_declared_hash():
    p = _with_restricted(["hidden-one.example"])
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(p, _feeds(), restricted=["other.example"], serial=1)
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(p, _feeds(), serial=1)  # declared but not supplied
    with pytest.raises(policy.PolicyError):
        policy.compile_rpz(policy.load(EXAMPLE), _feeds(), restricted=["hidden-one.example"], serial=1)  # undeclared


@pytest.mark.parametrize(
    "key,value",
    [
        ("profile", "university"),
        ("version", 0),
        ("valid_days", 0),
        ("reason_code", 9),
        ("scope", "Giga-AR-primary"),
        ("threat_feeds", [{"provider": "x"}]),
        ("categories", ["malware", "malware"]),
        ("unexpected", True),
    ],
)
def test_schema_rules_are_enforced_at_runtime(key, value):
    doc = copy.deepcopy(policy.load(EXAMPLE).doc)
    doc[key] = value
    with pytest.raises(policy.PolicyError):
        policy.validate(doc)


def test_rules_digest_ignores_renewal_fields_only():
    # ADR-0012: a renewal changes version, reason code and validity, not what is blocked.
    p = policy.load(EXAMPLE)
    renewed = copy.deepcopy(p.doc)
    renewed["version"] = p.doc["version"] + 1
    renewed["reason_code"] = 2
    renewed["valid_days"] = 30
    r = policy.validate(renewed)
    assert r.content_hash() != p.content_hash()
    assert r.rules_digest() == p.rules_digest()

    changed = copy.deepcopy(renewed)
    changed["local_blocks"].append({"domain": "new-block.example", "reason": "test"})
    assert policy.validate(changed).rules_digest() != p.rules_digest()

    for key in ("categories", "exceptions", "feed_hashes", "restricted_list_hash", "scope", "profile"):
        assert key not in policy.RENEWAL_KEYS


def test_rules_digest_is_not_a_content_hash():
    p = policy.load(EXAMPLE)
    assert p.rules_digest() != p.content_hash()
