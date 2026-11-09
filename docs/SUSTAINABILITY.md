# Sustainability and operating cost

*CC BY 4.0 · Draft. Figures marked **[M1]** are produced during milestone M1 (design and sign-off) from quotes in the pilot region and testnet measurements. They are left empty here on purpose rather than estimated without data.*

A school filter that stops when the pilot money stops does not protect anyone. This page sets out what it costs to run the system per school, who can run it after the pilot, what they receive, and what happens if funding ends.

## 1. Cost model

Costs fall into three groups. The first two grow with the number of schools; the third is per scope, not per school.

| Line item | Driver | How it is computed | Estimate per school per month |
| --- | --- | --- | --- |
| Resolver hosting | Two instances per region, sized for peak queries per second | (monthly cost of the resolver pair) ÷ (schools served) | [M1] |
| Bandwidth and logging-free monitoring | Queries per school per day | Provider pricing × query volume | [M1] |
| Reviewer test runs | One test per school per attestation cycle (≤ 90 days) | (reviewer day rate × hours per school) ÷ months per cycle | [M1] |
| Attestation gas (OP Mainnet) | Two attestations per school per cycle | gas per attestation × gas price × 2 ÷ months per cycle | [M1, measured on OP Sepolia] |
| Daily root anchoring | One transaction per scope per day | gas per `commitRoot` × gas price × 30 ÷ schools in the scope | [M1, measured on OP Sepolia] |
| Policy updates | One transaction per version, at least one per 90 days | gas per `publishPolicy` × gas price × versions per month ÷ schools in the scope | [M1, measured on OP Sepolia] |
| Proof generation (ZK, from M4) | One proof per scope per day | prover machine cost per hour × proving hours per day × 30 ÷ schools in the scope | [M4 benchmarks, VPR-036] |
| Proof verification gas | One verification per scope per day | verifier gas × gas price × 30 ÷ schools in the scope | [M4 benchmarks, VPR-036] |

Fixed costs per country, not per school: dashboard hosting, document and dataset mirroring, annual external review of the resolver configuration, and staff time for policy renewal and appeals. These are listed in the playbook for new countries (VPR-064) with the same method.

Two properties of the design keep the marginal cost low. On-chain activity per scope is constant per day, so its share per school falls as a scope grows. Filtering itself runs on ordinary resolver infrastructure, with no per-query fee to any third party.

## 2. Who operates after the pilot

| Option | Who runs the resolver | Who publishes roots and proofs | Fits when |
| --- | --- | --- | --- |
| Ministry of Education | The ministry's IT unit or its contractor | The same unit, under its own key | The ministry already operates national education networks |
| Connectivity provider | The ISP contracted to connect the schools, as part of the service | The ISP, under its own key | Giga or the ministry contracts connectivity per school |
| Hosted by Giga or a regional partner | A shared regional deployment | The hosting partner | Several countries want the service without running infrastructure |
| Xcapit under contract | Xcapit, as operator | Xcapit | Transitional, while one of the options above is prepared |

In every option, the separation of roles in [ADR-0005](adr/0005-issuer-separation.md) is kept: whoever operates the resolver does not test it and does not sign the policy alone. Changing the operator is an operational change, not a protocol change: the governor rotates the anchor publisher with `setPublisher`, and the new operator attests its deployments.

## 3. Handover package

At the end of the pilot, the operator taking over receives:

- runbooks for the resolver pair, the synchronisation daemon, the exporter, the daily job and the prover;
- the playbook for new countries (VPR-064), including scope charters and profile templates;
- a key ceremony for each institutional signer of the governor Safe, with documented recovery and rotation;
- the published datasets, policy documents and attestations to date, all of which remain public;
- a briefing for the independent reviewer on the test kit (VPR-018).

## 4. If funding stops

- **Filtering continues.** The resolver does not depend on the chain. It keeps enforcing the last verified policy version.
- **Expiry still applies.** When that version expires without renewal, the scope falls back to what its charter defines (recommended: protective categories only). No content restriction outlives its authorisation.
- **Records freeze, they do not disappear.** No new roots, proofs or attestations are published, but everything already on-chain and mirrored remains verifiable.
- **Attestations lapse.** Without new tests, independent test attestations reach `validUntil`, and dashboards stop showing schools as protected. This is intended: the public record tells the truth about the state of the service.

## 5. Open inputs

- [ ] Resolver hosting quotes in the pilot region (M1, week 1).
- [ ] Reviewer day rate and hours per school (M1, week 2).
- [ ] Gas per operation measured on OP Sepolia (M2, week 5).
- [ ] Proving cost per scope per day (M4, VPR-036).
- [ ] Agreement with Giga and the ministry on the post-pilot operator (before the end of phase 1).
