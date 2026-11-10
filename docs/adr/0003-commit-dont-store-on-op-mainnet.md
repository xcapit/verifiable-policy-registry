# ADR-0003: Commit, do not store: hashes on OP Mainnet with EAS

- Status: Accepted
- Date: 2026-11-09

## Context

We need a record of policies, attestations and metrics that no single party (government, UN agency, operator) can rewrite. Putting documents on-chain is expensive and risks publishing data that should not be permanent.

## Decision

- The chain stores only commitments: content hashes, signatures, expiry, appeal status and daily Merkle roots. Documents and datasets live off-chain (HTTPS or IPFS) and are verified against those commitments.
- Network: OP Mainnet, because EAS is deployed there and fees are low. Base is the fallback.
- Attestations use the Ethereum Attestation Service; formats stay compatible with W3C Verifiable Credentials 2.0 where possible.

## Consequences

Availability of documents depends on the publisher; mirrors (IPFS pinning, GitHub) are required by the deployment playbook. Contracts stay small and cheap to audit.

## Alternatives considered

A permissioned ledger run by the partners: cheaper, but the partners would be verifying themselves. Ethereum L1: no sequencer and no L2 upgrade keys, but every anchor, policy version and attestation costs L1 gas, and attestations grow with the number of schools.
