# Public-goods case

*CC BY 4.0 · Part of the ESP evidence package ([index](APPLICATION_EVIDENCE_INDEX.md)). This package describes the project for an Ethereum Foundation Ecosystem Support Program (ESP) application. It is not an application, it does not claim eligibility, and it implies no ESP review or endorsement.*

> **Before submitting:** maintainers must verify the current official ESP route (open application, Wishlist item or RFP) and its requirements at <https://esp.ethereum.foundation/applicants>. Routes, eligibility rules and formats change; nothing in this package substitutes for that check.

## 1. Problem

Institutions increasingly enforce policies on networks they do not fully control: content filters on school or library networks, service-level commitments of public utilities, eligibility rules of aid programmes. The people affected by these policies, and the funders who pay for them, usually have no way to check three things: which policy is in force, who authorised it, and whether the figures reported about its effect were altered after the fact. When the operator of the enforcement is also the custodian of its records, the records prove little.

The problem has two technical halves:

1. **Policy accountability.** A public, append-only record of policy versions that a threshold of independent parties must authorise, that expire by default and that can be contested.
2. **Aggregate accountability without surveillance.** Impact figures that cannot be rewritten after publication, that anyone can recompute, and that never contain individual-level data.

Neither half is specific to schools. The connected-school use case with UNICEF Giga is one reference deployment of a more general pattern.

## 2. Why Ethereum, and what it does not solve

| Property needed | What Ethereum (via an L2) contributes | Evidence |
| --- | --- | --- |
| A history no single party can rewrite | Append-only contract state with public events; global agreement on order | [`contracts/src/VerifiablePolicyRegistry.sol`](../../contracts/src/VerifiablePolicyRegistry.sol) |
| Threshold authorisation across institutions | The governor is any address, typically a Safe multisig; the contract does not re-implement multisig logic | [ADR-0004](../adr/0004-multisig-governor-expiry-appeals.md) |
| Separation of who operates and who certifies | EAS attestations under three schemas, with issuer roles recorded per scope on-chain | [`schemas/eas-schemas.json`](../../schemas/eas-schemas.json), [ADR-0005](../adr/0005-issuer-separation.md) |
| Publicly checkable aggregates | Write-once daily roots and on-chain verification of a single published row | [`contracts/src/MetricsAnchor.sol`](../../contracts/src/MetricsAnchor.sol) |
| Contestability without wallets for end users | Appeals recorded as document hashes; a relayer can file them | [INTERFACES I9](../INTERFACES.md) |

The ledger does **not** prove that an enforcement point behaves as declared, that an event log is complete, or that a restricted list was actually applied. These limits are stated in the [white paper](../WHITEPAPER.md) (§6.1 and §11) and in the [threat model](../security/THREAT_MODEL.md), and they are the reason the design keeps an independent reviewer and an audit in the loop.

**Trust assumptions and portability.** The proposed network is OP Mainnet, an OP Stack rollup. Its safety relies on Ethereum L1 and its fault-proof system, while ordering and liveness depend on a sequencer that can delay or censor transactions. In that case transactions can be forced through L1, at higher cost and latency. Filtering itself does not depend on the chain's liveness. The contracts use no L2-specific features and run on any EVM chain. EAS is deployed on several networks, and the schemas are CC0. The open portability questions — chain identity in a deployment manifest, confirmation depth and migration — are tracked as VPR-049 and in the threat model.

## 3. Open-source public-goods outputs

All outputs are open and reusable without permission: code under AGPL-3.0-only, schemas under CC0-1.0, documentation under CC BY 4.0 ([NOTICE](../../NOTICE), [ADR-0002](../adr/0002-licensing.md)).

| Output | Status at v0.2 | Who can reuse it |
| --- | --- | --- |
| Policy registry pattern: versions, reasons, mandatory expiry, appeals by document hash, on-chain issuer roles | Implemented, tested, not audited | Any governed policy with a bounded audience |
| `MetricsAnchor`: write-once daily roots, row verification with domain-separated, day-bound leaves | Implemented, tested, not audited | Any programme publishing aggregate counts |
| EAS schemas for deployment, independent test and conformance attestations | Defined, not yet registered on a network | Any scheme where operators must not certify themselves |
| `vpr` toolkit: canonical hashing, aggregation with small-cell suppression, Merkle proofs, verification CLI | Implemented, tested | Integrators and independent verifiers ([integration guide](../toolkit/INTEGRATION_GUIDE.md)) |
| End-to-end demonstrator with synthetic data | Implemented, run in CI | Reviewers and new integrators |
| Zero-knowledge proof of correct suppressed aggregation | Designed; not implemented ([evidence pack](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md)) | Any aggregate-reporting programme wanting more than a commitment |

The second reference use case, which is not about schools, is in [`examples/public-service/`](../../examples/public-service). It is a synthetic public-service reliability dataset verified by the same generic verifier, and it shows that the toolkit does not depend on school-specific logic.

## 4. Alignment with CROPS

The ESP describes its priorities in terms of censorship resistance, open source, privacy and security (CROPS). The project relates to them as follows. This is a description of intent and evidence, not a claim that the ESP shares this reading:

- **Censorship resistance.** The design does not make filtering impossible to abuse. It makes every policy change public, signed, temporary and contestable, so that over-blocking becomes visible and reversible ([white paper](../WHITEPAPER.md) §6.2, adversary A2).
- **Open source.** All code, schemas and documents are public under OSI-approved or Creative Commons licences.
- **Privacy.** Nothing identifying leaves the resolver process. Published data is limited to suppressed aggregates, and its residual risks are analysed rather than denied ([privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md)).
- **Security.** The contracts are kept minimal, an external audit is planned before mainnet, and negative tests cover tampering ([claims and evidence](../CLAIMS_AND_EVIDENCE.md)).

## 5. What is not proposed

No token, no fee-bearing service, no proprietary component and no single-customer deliverable. The connected-school deployment is a validation environment. Its operation, hosting and country-specific costs are outside the scope proposed to the ESP ([sustainability](../SUSTAINABILITY.md)).
