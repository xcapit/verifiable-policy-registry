import pytest

from vpr import merkle, metrics
from vpr.hashing import to_hex

D = "2026-11-01"

# Shared test vector (also in contracts/test/MetricsAnchor.test.js).
VECTOR_ROWS = [
    metrics.Row("giga-0001", D, "adult", 40),
    metrics.Row("giga-0001", D, "malware", 25),
    metrics.Row("giga-0003", D, "malware", 25),
]
VECTOR_LEAF0 = "0xd16b6d8f55bf68aa54ca8d755e0c0beb5c84c2e63e9eda7ab55abc5579b8a348"
VECTOR_ROOT = "0x7d91cbb18fd37a7042393e2043b2fed8a1d0723bdf8845d72bc7188febdf6747"


def test_small_cells_are_suppressed():
    events = [("s1", D, "malware")] * 12 + [("s1", D, "adult")] * 3
    rows, suppressed = metrics.aggregate(events, k=10)
    assert rows == [metrics.Row("s1", D, "malware", 12)]
    assert suppressed == 1


def test_k_must_be_meaningful():
    with pytest.raises(ValueError):
        metrics.aggregate([], k=1)


def test_root_is_order_independent_and_recomputable():
    events = [("s1", D, "malware")] * 10 + [("s2", D, "phishing")] * 11 + [("s3", D, "adult")] * 12
    rows, _ = metrics.aggregate(events, k=10)
    rows_rev, _ = metrics.aggregate(list(reversed(events)), k=10)
    assert metrics.dataset_root(rows) == metrics.dataset_root(rows_rev)
    # anyone holding only the published CSV can recompute the root
    assert metrics.dataset_root(metrics.read_csv(metrics.to_csv(rows))) == metrics.dataset_root(rows)


def test_proofs_verify_for_every_row():
    events = []
    for i in range(7):
        events += [(f"s{i}", D, "malware")] * (10 + i)
    rows, _ = metrics.aggregate(events, k=10)
    root = merkle.root([r.leaf() for r in rows])
    for i, r in enumerate(rows):
        path = merkle.proof([x.leaf() for x in rows], i)
        assert merkle.verify(r.leaf(), path, root)


def test_shared_vector_matches_solidity():
    assert to_hex(VECTOR_ROWS[0].leaf()) == VECTOR_LEAF0
    assert metrics.dataset_root(VECTOR_ROWS) == VECTOR_ROOT


def test_leaves_and_nodes_are_domain_separated():
    a, b = VECTOR_ROWS[0].leaf(), VECTOR_ROWS[1].leaf()
    # an internal node is not the hash of the plain concatenation, and no leaf equals it
    assert merkle.hash_pair(a, b) not in {r.leaf() for r in VECTOR_ROWS}
    assert merkle.hash_pair(a, b) != merkle.keccak256(min(a, b) + max(a, b))


def test_leaf_binds_the_day():
    r1 = metrics.Row("s1", "2026-11-01", "malware", 12)
    r2 = metrics.Row("s1", "2026-11-02", "malware", 12)
    assert r1.leaf() != r2.leaf()


def test_release_must_cover_one_day():
    with pytest.raises(ValueError):
        metrics.dataset_root([metrics.Row("s1", "2026-11-01", "c", 10), metrics.Row("s1", "2026-11-02", "c", 10)])


def test_release_rejects_duplicates_bad_dates_and_bad_counts():
    with pytest.raises(ValueError):
        metrics.dataset_root([metrics.Row("s1", D, "c", 10), metrics.Row("s1", D, "c", 11)])
    with pytest.raises(ValueError):
        metrics.dataset_root([metrics.Row("s1", "not-a-date", "c", 10)])
    with pytest.raises(ValueError):
        metrics.Row("s1", D, "c", 0).leaf()
    with pytest.raises(ValueError):
        metrics.validate_release([metrics.Row("s1", D, "c", 3)], k=10)


def test_encoding_is_unambiguous_with_separators_in_fields():
    # length prefixes: moving a character between fields changes the leaf
    assert metrics.Row("s|1", D, "c", 10).leaf() != metrics.Row("s", D, "1|c", 10).leaf()


def test_public_summary_omits_suppression_count():
    rows, _ = metrics.aggregate([("s1", D, "malware")] * 12 + [("s1", D, "adult")] * 2, k=10)
    summary = metrics.to_json(rows, 10)
    assert "suppressed" not in summary
    assert '"format": "vpr-dataset/2"' in summary
