# Public-goods case

*CC BY 4.0 · Part of the ESP evidence package ([index](APPLICATION_EVIDENCE_INDEX.md)). This package describes the project for an Ethereum Foundation Ecosystem Support Program (ESP) application. It is not an application, it does not claim eligibility, and it implies no ESP review or endorsement.*

> **Current route boundary (checked 2026-11-09):** ESP lists no active Wishlist, RFP or open round. Office Hours provide non-financial guidance and are not a funding application. This case must be matched to a future published funding opportunity before it can support a submission.

## 1. Problem

Institutions enforce policies on networks they do not fully control: content filters on school or library networks, service-level commitments of public utilities, eligibility rules of aid programmes. The people affected by these policies, and the funders who pay for them, usually have no way to check three things: which policy is in force, who authorised it, and whether the figures reported about its effect were altered after the fact. When the operator of the enforcement is also the custodian of its records, the records prove little.

The problem has two technical halves:

1. **Policy accountability.** A public, append-only record of policy versions that a threshold of independent parties must authorise, that expire by default and that can be contested.
2. **Aggregate accountability with data minimisation.** Impact releases that cannot be changed without detection after anchoring, that anyone can recompute, and whose implemented schema contains no individual-level fields.

Neither half is specific to schools. A proposed connected-school use case (schools connected by UNICEF Giga; no Giga commitment exists) is one reference application of a more general pattern.

## 2. Why Ethereum, and what it does not solve

| Property needed | What Ethereum (via an L2) contributes | Evidence |
| --- | --- | --- |
| A history no single party can rewrite | Append-only contract state with public events; global agreement on order | [`contracts/src/VerifiablePolicyRegistry.sol`](../../contracts/src/VerifiablePolicyRegistry.sol) |
| Designed threshold authorisation across institutions | The registry trusts one governor address. The proposed deployment uses a Safe multisig; threshold enforcement is external to this contract and Unverified until deployment | [ADR-0004](../adr/0004-multisig-governor-expiry-appeals.md) |
| Designed separation of who operates and who certifies | Three EAS schemas are defined and issuer roles are recorded in the registry; a schema resolver that enforces them at issuance is implemented and tested (`IssuerRoleResolver`); registration on a public network is Planned (M2) | [`schemas/eas-schemas.json`](../../schemas/eas-schemas.json), [ADR-0005](../adr/0005-issuer-separation.md) |
| Publicly checkable aggregates | Write-once daily roots and on-chain verification of a single published row | [`contracts/src/MetricsAnchor.sol`](../../contracts/src/MetricsAnchor.sol) |
| Contestability without wallets for end users | Appeal hashes and resolution status are Implemented; the walletless relayer is Planned (VPR-017) | [INTERFACES I9](../INTERFACES.md) |

The ledger does **not** prove that an enforcement point behaves as declared, that an event log is complete, or that a restricted list was actually applied. These limits are stated in the [white paper](../WHITEPAPER.md) (§6.1 and §11) and in the [threat model](../security/THREAT_MODEL.md), and they are the reason the design keeps an independent reviewer and an audit in the loop.

**Trust assumptions and portability.** The proposed network is OP Mainnet, an OP Stack rollup. Its safety relies on Ethereum L1 and its fault-proof system, while ordering and liveness depend on a sequencer that can delay or censor transactions. In that case transactions can be forced through L1, at higher cost and latency. Filtering itself does not depend on the chain's liveness. The contracts use no L2-specific features and should run on EVM chains that support the opcodes emitted by solc 0.8.24 (including PUSH0); no chain other than the local Hardhat network has been tested. EAS is deployed on several networks, and the schemas are CC0. The open portability questions — chain identity in a deployment manifest, confirmation depth and migration — are tracked as VPR-049 and in the threat model.

## 3. Open-source public-goods outputs

All outputs are open and reusable without permission: contracts and verifier under Apache-2.0, other code under AGPL-3.0-only, schemas and published datasets under CC0-1.0, documentation under CC BY 4.0 ([NOTICE](../../NOTICE), [ADR-0011](../adr/0011-licence-split-and-dataset-licence.md)).

| Output | Status on the v0.3 candidate branch | Who can reuse it |
| --- | --- | --- |
| Policy registry pattern: versions, reasons, mandatory expiry, appeals by document hash, on-chain issuer roles | Implemented, tested, not audited | Any governed policy with a bounded audience |
| `MetricsAnchor`: daily roots anchored once, with public governor corrections, row verification with domain-separated, day-bound leaves | Implemented, tested, not audited | Any programme publishing aggregate counts |
| EAS schemas for deployment, independent test and conformance attestations | Defined, not yet registered on a network | Any scheme where operators must not certify themselves |
| `vpr` toolkit: canonical hashing, aggregation with small-cell suppression, Merkle proofs, verification CLI | Implemented, tested | Integrators and independent verifiers ([integration guide](../toolkit/INTEGRATION_GUIDE.md)) |
| End-to-end demonstrator with synthetic data | Implemented, run in CI | Reviewers and new integrators |
| Zero-knowledge proof of correct suppressed aggregation | Designed; not implemented ([evidence pack](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md)) | Any aggregate-reporting programme wanting more than a commitment |

The second reference use case, which is not about schools, is in [`examples/public-service/`](../../examples/public-service). It is a synthetic public-service reliability dataset verified by the same generic verifier, and it shows that the toolkit does not depend on school-specific logic.

## 4. Alignment with CROPS

The ESP describes its priorities in terms of censorship resistance, open source, privacy and security (CROPS). The project relates to them as follows. This is a description of intent and evidence, not a claim that the ESP shares this reading:

- **Censorship resistance.** The tension is real: VPR provides accountability for institutional blocking, not censorship resistance in the CROPS sense, and the ESP may judge it out of scope. The design does not make filtering impossible to abuse. The implemented registry makes policy commitments, reasons, appeal status and contractual expiry public. Threshold signing, resolver behaviour after expiry and external recourse depend on the proposed deployment model ([white paper](../WHITEPAPER.md) §6.2, adversary A2).
- **Open source.** All code, schemas and documents are public under OSI-approved or Creative Commons licences.
- **Privacy.** The design permits only `(unit_id, day, category)` events to leave the resolver process, and the implemented aggregator rejects extra input fields and publishes only thresholded aggregates. The resolver and exporter are not implemented or audited, so the end-to-end property remains Designed ([privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md)).
- **Security.** The contracts are kept minimal, an external audit is planned before mainnet, and negative tests cover tampering ([claims and evidence](../CLAIMS_AND_EVIDENCE.md)).

## 5. What is not proposed

No token, no proprietary component and no single-customer deliverable. A grant would fund only the open outputs. Xcapit may offer paid operation of a deployment outside any grant ([sustainability](../SUSTAINABILITY.md), operator option 4); this would be disclosed, and the operator would remain separated from testing and governance (ADR-0005). The connected-school alpha is a validation environment; its operation, hosting and reviewer costs are outside the scope proposed to the ESP and need separate funding, which is not yet identified.
