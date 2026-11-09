"""The generic toolkit API: no school-specific logic, same verifier for every use case."""

from pathlib import Path

import pytest

from vpr import policy, toolkit

ROOT = Path(__file__).resolve().parents[2]
SCHOOL_EVENTS = ROOT / "examples" / "events.csv"
SERVICE_EVENTS = ROOT / "examples" / "public-service" / "events.csv"
POLICY = ROOT / "policies" / "example-primary.yaml"
FEEDS = ROOT / "examples" / "feeds"


def _release(path, day=None):
    from vpr import metrics

    events = metrics.read_events(path.read_text(encoding="utf-8"))
    if day:
        events = [e for e in events if e[1] == day]
    return toolkit.aggregate(events, 10)


@pytest.mark.parametrize("path,day", [(SCHOOL_EVENTS, "2026-11-01"), (SERVICE_EVENTS, None)])
def test_two_use_cases_verify_with_the_same_generic_verifier(path, day):
    rows = _release(path, day)
    root = toolkit.release_root(rows)
    for i, r in enumerate(rows):
        assert toolkit.verify_row(r, toolkit.row_proof(rows, i), root)
    # a release written with the generic unit column reads back to the same root
    assert toolkit.release_root(toolkit.read_release(toolkit.write_release(rows, "unit_id"))) == root


def test_unit_column_name_does_not_change_the_commitment():
    rows = _release(SCHOOL_EVENTS, "2026-11-01")
    a = toolkit.read_release(toolkit.write_release(rows, "unit_id"))
    b = toolkit.read_release(toolkit.write_release(rows, "school_id"))
    assert toolkit.release_root(a) == toolkit.release_root(b)


def test_tampered_row_wrong_root_and_wrong_day_are_rejected():
    rows = _release(SERVICE_EVENTS)
    root = toolkit.release_root(rows)
    proof = toolkit.row_proof(rows, 0)
    r = rows[0]
    assert not toolkit.verify_row(toolkit.Row(r.school_id, r.day, r.category, r.count + 1), proof, root)
    assert not toolkit.verify_row(toolkit.Row(r.school_id, "2026-11-04", r.category, r.count), proof, root)
    assert not toolkit.verify_row(r, proof, "0x" + "00" * 32)


def test_document_hash_matches_policy_content_hash():
    p = policy.load(POLICY)
    assert toolkit.document_hash(p.doc) == p.content_hash()


def _zone():
    p = policy.load(POLICY)
    feeds = {f.stem: policy.load_feed(f) for f in FEEDS.glob("*.txt")}
    return policy.compile_rpz(p, feeds, block_page="block.example.org", serial=1)


@pytest.mark.parametrize(
    "domain,action,source",
    [
        ("wikipedia.org", "passthru", None),
        ("en.wikipedia.org", "passthru", None),
        ("bad-malware.example", "redirect", "category:malware"),
        ("cdn.bad-malware.example", "redirect", "category:malware"),
        ("casino-example.example", "redirect", "local"),
        ("neutral-site.example", "allow", None),
    ],
)
def test_zone_evaluation(domain, action, source):
    r = policy.evaluate_zone(_zone(), domain)
    assert r["action"] == action
    assert r["source"] == source


def test_zone_evaluation_does_not_label_restricted_entries():
    p = policy.load(POLICY)
    doc = dict(p.doc, restricted_list_hash=policy.restricted_list_hash(["hidden-one.example"]))
    p2 = policy.validate(doc)
    feeds = {f.stem: policy.load_feed(f) for f in FEEDS.glob("*.txt")}
    zone = policy.compile_rpz(p2, feeds, restricted=["hidden-one.example"], serial=1)
    for d in ("hidden-one.example", "www.hidden-one.example"):
        r = policy.evaluate_zone(zone, d)
        assert r["action"] == "nxdomain" and r["source"] == "unlabelled"


def test_exact_rule_beats_wildcard():
    zone = "a.example CNAME rpz-passthru.\n*.example CNAME . ; local\n"
    assert policy.evaluate_zone(zone, "a.example")["action"] == "passthru"
    assert policy.evaluate_zone(zone, "b.example")["action"] == "nxdomain"
