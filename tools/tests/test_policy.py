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
    feeds = {f.stem: policy.load_feed(f) for f in FEEDS.glob("*.txt")}
    zone = policy.compile_rpz(p, feeds, block_page="block.example.org", serial=1)
    assert "wikipedia.org CNAME rpz-passthru." in zone
    assert "wikipedia.org CNAME block.example.org." not in zone
    assert "bad-malware.example CNAME block.example.org." in zone
    assert "casino-example.example CNAME block.example.org." in zone


def test_restricted_entries_are_not_labelled():
    p = policy.load(EXAMPLE)
    zone = policy.compile_rpz(p, {}, restricted=["hidden-one.example"], serial=1)
    line = next(l for l in zone.splitlines() if l.startswith("hidden-one.example"))
    assert ";" not in line  # no source label: the zone must not reveal which entries come from the restricted list


def test_restricted_list_hash_is_order_independent():
    a = policy.restricted_list_hash(["b.example", "a.example"])
    b = policy.restricted_list_hash(["a.example", "b.example", "a.example"])
    assert a == b
