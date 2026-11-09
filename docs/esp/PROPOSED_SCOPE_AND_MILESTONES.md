# Proposed scope and milestones

*CC BY 4.0 · Part of the ESP evidence package ([index](APPLICATION_EVIDENCE_INDEX.md)). Proposed work only: nothing here is funded, approved or scheduled with any funder. As checked on 2026-11-09, ESP has no active Wishlist, RFP or open round; this scope is not submit-ready and must be adapted to a future published opportunity.*

## 1. Existing work, not part of a future request

The following exist at v0.2 ([v0.2.0 release](https://github.com/xcapit/verifiable-policy-registry/releases/tag/v0.2.0)) and are offered as the starting point, not as deliverables of a grant:

| Component | Evidence | Status |
| --- | --- | --- |
| `VerifiablePolicyRegistry` | [`contracts/src/VerifiablePolicyRegistry.sol`](../../contracts/src/VerifiablePolicyRegistry.sol), [tests](../../contracts/test/VerifiablePolicyRegistry.test.js) | Implemented, tested in CI, not audited |
| `MetricsAnchor` with `verifyRow` | [`contracts/src/MetricsAnchor.sol`](../../contracts/src/MetricsAnchor.sol), [tests](../../contracts/test/MetricsAnchor.test.js) | Implemented, tested in CI, not audited |
| `vpr` tools and CLI | [`tools/vpr/`](../../tools/vpr), [tests](../../tools/tests) | Implemented, tested in CI |
| EAS schema definitions | [`schemas/eas-schemas.json`](../../schemas/eas-schemas.json) | Defined, not registered |
| End-to-end demonstrator | [`examples/e2e/`](../../examples/e2e), CI job `e2e` | Implemented on a local Hardhat network |
| Specifications | [INTERFACES](../INTERFACES.md), [ARCHITECTURE](../ARCHITECTURE.md), [ADRs](../adr) | Published |

v0.3 adds evidence material and a generic toolkit boundary. Its exact status is in [CLAIMS_AND_EVIDENCE](../CLAIMS_AND_EVIDENCE.md).

## 2. Candidate scope for a future relevant funding opportunity

The proposal follows phase 1 of the [roadmap](../ROADMAP.md): four months, three gates. Tasks reference stable backlog IDs ([BACKLOG](../BACKLOG.md)). Shares are the roadmap's indicative split. Amounts are not set.

| Milestone | Weeks | Deliverables (public, reusable) | Acceptance method | Indicative share | Budget |
| --- | --- | --- | --- | --- | --- |
| M1 · Design and sign-off | 1–4 | Normative contract and EAS specifications (VPR-001, VPR-002); ZK relation specification binding chain id, verifier, scope, day, policy version and hash, category and school sets, *k*, log commitment, output root and format version (VPR-033); deployment manifest format (VPR-049); threat model (VPR-003) | Documents merged; ZK specification reviewed in the M1 design review (Gate A); an additional published review by a cryptographer outside the team is proposed but is a maintainer decision (TBD); every public input in the specification has a planned negative test | 15% | TBD — maintainer input required |
| M2 · Testnet reference implementation | 5–10 | Deployment scripts and manifest (VPR-010, VPR-049); EAS schemas registered with a schema resolver enforcing issuer roles (VPR-012); attestation CLI (VPR-013); policy publisher and sync daemon (VPR-014, VPR-015); reviewer test kit (VPR-018) | Contracts verified on OP Sepolia at addresses listed in the manifest; an attestation from an address without the role is rejected by the resolver (test and on-chain transaction published); the demonstrator runs against OP Sepolia from a clean checkout | 35% | TBD — maintainer input required |
| M3 · Audit and registry on mainnet | 9–16 | Static analysis and invariant tests (VPR-040, VPR-042); external audit of the registry and anchor (VPR-024); gas report (VPR-041); integration guide for third-party builders | Audit report public with no open high-severity finding (binary); invariants of the white paper §3.3 encoded as fuzz/invariant tests passing in CI; registry and anchor on OP Mainnet only if the audit condition holds (Gate C) | 25% | TBD — maintainer input required |
| M4 · ZK aggregation reference implementation | 5–16 | Python oracle (VPR-034); circuit or zkVM program (VPR-030); benchmarks (VPR-036); testnet verifier (VPR-035); `vpr verify-proof` (VPR-037) | Oracle and circuit agree on a published randomised test set; negative tests reject a wrong chain, contract, scope, day, policy, category set, school set, *k*, replay and tampered proof; proving time, memory, proof size and verifier gas published for a stated hardware profile; a party outside the team verifies one proof with the CLI | 25% | TBD — maintainer input required |

In phase 1 the ZK circuit is **not** audited and **not** deployed on mainnet. A circuit audit and mainnet verifier belong to a separately agreed phase 2.

## 3. Out of scope for a candidate future request

- Operation of resolvers and onboarding of schools, which is country deployment work ([Giga package](../giga/PILOT_READINESS.md)).
- Any pilot outcome that depends on a ministry, a connectivity provider or UNICEF decisions. The roadmap's Gate B alpha is a validation step, not a grant deliverable.
- DPGA recognition. Submitting the application is planned; recognition is an outcome decided by the DPGA.

## 4. Team

Current maintainers are listed in [MAINTAINERS.md](../../MAINTAINERS.md). Time allocation per person and per milestone: **TBD — maintainer input required**. No commitment is implied by this document.

## 5. Reporting

If funded under a compatible opportunity, each milestone would close with a tagged release, a CHANGELOG entry, acceptance evidence linked from [APPLICATION_EVIDENCE_INDEX](APPLICATION_EVIDENCE_INDEX.md), and an update of the [claims ledger](../CLAIMS_AND_EVIDENCE.md).
