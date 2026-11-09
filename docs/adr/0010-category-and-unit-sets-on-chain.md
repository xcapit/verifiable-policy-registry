# ADR-0010: Category and unit sets committed on-chain for the ZK relation

- Status: Proposed (Designed, not implemented)
- Date: 2026-11-09

## Context

The planned zero-knowledge proof must show that every event's category belongs to the policy in force and that every event comes from an admitted unit. Recomputing the policy's content hash (keccak-256 over canonical JSON) inside a circuit is expensive. Taking the category set as a free public input supplied by the prover would make the binding optional, so it would not be a binding.

## Decision

The governor records, next to each policy version, a commitment `catRoot` to the sorted set of category labels and the threshold `k`. For each scope it also records a commitment `unitRoot` to the admitted units. The verifier contract reads `catRoot`, `unitRoot` and `k` from the registry for `(scopeId, policyVersion)`; the prover never supplies them. Tools and the dashboard check that `catRoot` matches the categories of the published document. Full specification: [cryptographic evidence §6](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md).

## Consequences

The registry interface changes in M4 (VPR-058), which needs a new deployment, since the contracts are not upgradeable. The binding between the document and `catRoot` is checked off-chain by anyone, not by the chain. That is acceptable because the document is public and its hash is on-chain.

## Alternatives considered

Hashing the full document in the circuit: correct but costly. A SNARK-friendly hash of the document as a second content hash: adds a second canonical hash that every tool would need to maintain.
