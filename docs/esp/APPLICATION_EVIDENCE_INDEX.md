# Application evidence index

*CC BY 4.0 · Entry point of the ESP evidence package. Each assertion an application might make is mapped to the file that supports it and to its status. The package is a preparation aid; it is not an application and implies no review or endorsement by the Ethereum Foundation.*

> **Route status checked 2026-11-09:** the official ESP site lists no active Wishlist, RFP or open round. Office Hours remain available for non-financial guidance but are not a funding application. This package is therefore **Blocked** as an application until ESP publishes a relevant funding opportunity. Before any submission, match the scope to that opportunity and fill every field marked *TBD — maintainer input required*.

## Package contents

| Document | Purpose |
| --- | --- |
| [PUBLIC_GOODS_CASE](PUBLIC_GOODS_CASE.md) | Problem, why Ethereum, outputs, CROPS alignment |
| [PROPOSED_SCOPE_AND_MILESTONES](PROPOSED_SCOPE_AND_MILESTONES.md) | Existing work versus proposed milestones, with acceptance methods |
| [ECOSYSTEM_REUSE_AND_ADOPTION](ECOSYSTEM_REUSE_AND_ADOPTION.md) | Who can build on it and how adoption is measured |
| [RISKS_AND_DEPENDENCIES](RISKS_AND_DEPENDENCIES.md) | Delivery risks, external dependencies, L2 assumptions |

## Evidence map

| Assertion | Status | Evidence |
| --- | --- | --- |
| Policy versions are append-only, expire by default and need the governor | Implemented | [`VerifiablePolicyRegistry.sol`](../../contracts/src/VerifiablePolicyRegistry.sol), [tests](../../contracts/test/VerifiablePolicyRegistry.test.js) |
| Appeals store only a document hash; rejections carry a reason hash; resubmission opens a new round | Implemented | Same contract and tests; [INTERFACES I9](../INTERFACES.md) |
| Issuer roles are recorded per scope, one role per address | Implemented | Same contract and tests |
| The anchor publisher can only be appointed by the scope's governor | Implemented | [`MetricsAnchor.sol`](../../contracts/src/MetricsAnchor.sol), [tests](../../contracts/test/MetricsAnchor.test.js) |
| Rows are verified on-chain with domain-separated, day-bound leaves; tampered rows are rejected | Implemented | Same; shared vector in [`tools/tests/test_metrics.py`](../../tools/tests/test_metrics.py) |
| The toolkit verifies a non-school dataset with the same verifier | See ledger | [`examples/public-service/`](../../examples/public-service), [integration guide](../toolkit/INTEGRATION_GUIDE.md) |
| The local demonstrator runs from a clean checkout without credentials | Demonstrated in CI | [`examples/e2e/`](../../examples/e2e), [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) |
| Cryptographic encodings and the ZK relation are specified | Designed (ZK not implemented) | [ZK and cryptographic evidence](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md) |
| Threats and privacy risks are analysed with residual risks | Designed | [Threat model](../security/THREAT_MODEL.md), [privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md) |
| Performance figures | See report | [Benchmarks](../benchmarks/BENCHMARKS.md) (local and CI environments only; no production claims) |
| Contracts are audited | **Not true at v0.3.0** | Audit planned in M3 ([roadmap](../ROADMAP.md)) |
| Deployed on a public network | **Not true at v0.3.0** | Planned in M2 (testnet) and Gate C (mainnet) |
| Endorsement by the EF, UNICEF, Giga or DPGA | **None exists** | — |
| Per-claim status for the whole project | Ledger | [CLAIMS_AND_EVIDENCE](../CLAIMS_AND_EVIDENCE.md) |
| Guide for an independent reviewer | Prepared | [Reviewer guide](../review/V03_REVIEWER_GUIDE.md) |

## Fields requiring maintainer input

- Budget in USD per milestone, including the external audit: **TBD — maintainer input required**.
- Time allocation per team member: **TBD — maintainer input required**.
- Adoption targets: **TBD — maintainer input required**.
- Application route: **Blocked — no active Wishlist, RFP or open round on 2026-11-09; choose only after a relevant opportunity is published**.

The route is not merely an administrative field: eligibility and requested scope depend on the published Wishlist, RFP or round. No document in this directory should be submitted as a general or unsolicited funding application.
