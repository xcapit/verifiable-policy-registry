# ADR-0007: Threshold-suppressed metrics (k = 10) with a daily Merkle root

- Status: Accepted
- Date: 2026-11-09

## Context

Donors and partners need impact figures. Children must not be identifiable from them.

## Decision

- The resolver emits only `(school_id, day, category)` per block. No IPs, device identifiers or queried names leave it.
- Cells with fewer than k = 10 events are suppressed before publication.
- Each daily dataset is committed with a Merkle root (sorted-pair keccak256; OpenZeppelin-compatible in v0.1, domain-separated since dataset format 2 and therefore no longer verifiable with OpenZeppelin's `MerkleProof`), anchored in `MetricsAnchor`. Solidity and Python share the same test vector.

## Note (2026-11-09)

The threshold counts blocked queries per cell, not distinct children, so the mechanism is small-cell suppression rather than k-anonymity in the sense of Sweeney (2002). The decision stands; the wording in public documents was corrected accordingly (white paper §5.2).

## Consequences

Small schools will see many suppressed cells: reporting degrades before privacy does. Changing k or the leaf encoding is a breaking interface change.
