import pytest

from vpr import merkle, metrics
from vpr.hashing import keccak256, to_hex


def test_small_cells_are_suppressed():
    events = [("s1", "2026-11-01", "malware")] * 12 + [("s1", "2026-11-01", "adult")] * 3
    rows, suppressed = metrics.aggregate(events, k=10)
    assert rows == [metrics.Row("s1", "2026-11-01", "malware", 12)]
    assert suppressed == 1


def test_k_must_be_meaningful():
    with pytest.raises(ValueError):
        metrics.aggregate([], k=1)


def test_root_is_order_independent_and_recomputable():
    events = [("s1", "d", "malware")] * 10 + [("s2", "d", "phishing")] * 11 + [("s3", "d", "adult")] * 12
    rows, _ = metrics.aggregate(events, k=10)
    rows_rev, _ = metrics.aggregate(list(reversed(events)), k=10)
    assert metrics.dataset_root(rows) == metrics.dataset_root(rows_rev)
    # anyone holding only the published CSV can recompute the root
    assert metrics.dataset_root(metrics.read_csv(metrics.to_csv(rows))) == metrics.dataset_root(rows)


def test_proofs_verify_for_every_row():
    events = []
    for i in range(7):
        events += [(f"s{i}", "d", "malware")] * (10 + i)
    rows, _ = metrics.aggregate(events, k=10)
    root = merkle.root([r.leaf() for r in rows])
    for i, r in enumerate(rows):
        path = merkle.proof([x.leaf() for x in rows], i)
        assert merkle.verify(r.leaf(), path, root)


def test_merkle_matches_solidity_test_vector():
    # Same vector as contracts/test/MetricsAnchor.test.js: leaves = keccak256("a"), ("b"), ("c")
    a, b, c = (keccak256(x) for x in (b"a", b"b", b"c"))
    expected = merkle.hash_pair(merkle.hash_pair(a, b), c)
    assert merkle.root([a, b, c]) == expected
    assert merkle.verify(a, [b, c], expected)


def test_pipe_in_fields_is_rejected():
    with pytest.raises(ValueError):
        metrics.Row("s|1", "d", "c", 10).leaf()
