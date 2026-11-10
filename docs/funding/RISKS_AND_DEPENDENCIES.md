# Risks and dependencies

*CC BY 4.0 · Part of the funding evidence package ([index](EVIDENCE_INDEX.md)). The full threat model is in [THREAT_MODEL](../security/THREAT_MODEL.md); this page covers delivery risks for the proposed scope.*

## 1. Delivery risks

| Risk | Likelihood | Impact | Mitigation | Residual |
| --- | --- | --- | --- | --- |
| ZK proving cost too high for daily use on commodity hardware | Medium | M4 acceptance slips | Proving system chosen in weeks 5–7 from the M1 evaluation; benchmarks in weeks 10–12 decide per-school proving; fallback to per-school proofs; acceptance stays on testnet | Proof generation may need more hardware than an operator in the target region has |
| ZK relation underspecified, leading to an unsound proof | Medium | A proof that verifies but does not bind the intended context | Normative specification in M1 with every public input listed; negative tests per input. No independent cryptographic review is currently planned or budgeted; M1 sign-off is internal | Medium until an outside review is engaged |
| Audit capacity and timing | Medium | Gate C slips | Auditor booked in week 4; contract freeze in week 12; mainnet only after a clean report | Mainnet deployment may move past week 16 |
| Contract defect found after deployment | Low–medium | Corrupted or misleading record | Minimal contracts, invariant tests, audit; non-upgradeable contracts with documented migration ([white paper](../WHITEPAPER.md) §6.3) | Migration loses the canonical address |
| Low uptake by other builders | Medium | Limited ecosystem value | Generic toolkit, second use case, integration guide, CC0 schemas | Adoption cannot be guaranteed by the team |
| Small team (bus factor) | Medium | Delays | Six team members, all at Xcapit ([MAINTAINERS](../../MAINTAINERS.md)); resolver, deployment and CI have a single owner (F. Schillage), who also leads ZK engineering in M4 | Single-organisation and single-owner concentration; time allocation not yet confirmed (TBD — maintainer input required) |

## 2. External dependencies

| Dependency | Needed for | Status | If unavailable |
| --- | --- | --- | --- |
| OP Mainnet and OP Sepolia | Deployment | Public networks | EVM chains with EAS that support solc 0.8.24 opcodes; untested beyond the local Hardhat network |
| Ethereum Attestation Service | Attestations | Deployed on several networks | W3C Verifiable Credentials signed off-chain (weakens issuer separation: no on-chain role check) |
| Safe | Governor multisig | Open source, widely deployed | Any multisig or contract wallet, since the governor is an address |
| External auditor | Gate C | Not engaged | Mainnet deployment waits |
| Outside cryptographic reviewer | M1 ZK specification | Not engaged | M4 proceeds at higher risk; recorded as unreviewed |
| Pilot partners (Giga, ministry, provider) | Validation alpha only | No commitment exists | The reusable outputs remain deliverable on a synthetic deployment (roadmap Gate A) |
| Matching funding programme | Any grant application | Several programmes considered; none with an open call that matches the full scope as checked on 2026-11-10 ([FUNDING_ROUTES](FUNDING_ROUTES.md)) | Split the scope across programmes (tooling, audit, pilot operations); seek non-financial feedback (ESP Office Hours) |

## 3. L2-specific assumptions

Sequencer censorship or delay is mitigated by forced inclusion through L1. Clients must treat records as final only after the confirmation depth set in the deployment manifest (VPR-049, planned). An RPC split view would be detected by comparing several providers against the manifest, once VPR-049 exists. Gas for appeals is paid by the relayer, and its funding is an open item in the [sustainability model](../SUSTAINABILITY.md).
