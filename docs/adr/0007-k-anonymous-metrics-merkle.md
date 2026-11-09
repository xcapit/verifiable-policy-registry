# ADR-0007: k-anonymous metrics (k = 10) with a daily Merkle root

- Status: Accepted
- Date: 2026-11-09

## Context

Donors and partners need impact figures. Children must not be identifiable from them.

## Decision

- The resolver emits only `(school_id, day, category)` per block. No IPs, device identifiers or queried names leave it.
- Cells with fewer than k = 10 events are suppressed before publication.
- Each daily dataset is committed with a Merkle root (sorted-pair keccak256, OpenZeppelin-compatible), anchored in `MetricsAnchor`. Solidity and Python share the same test vector.

## Consequences

Small schools will see many suppressed cells: reporting degrades before privacy does. Changing k or the leaf encoding is a breaking interface change.
