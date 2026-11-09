# Roadmap

*CC BY 4.0 · Pilot plan: four months from the start of funding. Month 1 covers the design and its sign-off; months 2 to 4 cover the work: the registry, resolver and attestations, the metrics and the audit, and zero-knowledge proofs of aggregation. Payment shares per milestone are indicative.*

<p align="center"><img src="figures/roadmap.svg" alt="Sixteen-week pilot roadmap" width="100%"></p>

| Milestone | Weeks | Share | Ends with |
| --- | --- | --- | --- |
| M0 · Proof of concept | before funding | — | This repository (done) |
| M1 · Design and sign-off | 1–4 | 10% | Design, DPIA, privacy statement and ZK specification signed off |
| M2 · Registry, resolver and attestations | 5–10 | 35% | 20–50 schools attested; DPG application submitted |
| M3 · Metrics, dashboard and audit | 8–16 | 30% | Public audit; contracts on OP Mainnet; impact report validated |
| M4 · Zero-knowledge proofs of aggregation | 5–16 | 25% | Every daily release published with a proof verified on-chain |

The work milestones overlap on purpose. Metrics start as soon as the first school is attested, so the impact report rests on at least six weeks of data. The zero-knowledge track starts from the specification produced in M1, and its on-chain verifier is frozen together with the other contracts so that a single audit covers all of them.

## M0 · Proof of concept · done

- [x] `VerifiablePolicyRegistry` with versions, reasons, mandatory expiry, appeals and governor rotation
- [x] `MetricsAnchor` with write-once daily roots and on-chain proof verification
- [x] Python tooling: policy validation and hashing, RPZ compilation, aggregation with small-cell suppression, Merkle proofs, CLI
- [x] EAS schema definitions with separate issuer roles
- [x] Reference Unbound configuration
- [x] White paper, architecture, interfaces, decision records, governance, privacy statement draft

## M1 · Design and sign-off · weeks 1–4 · 10%

This month turns the proof of concept into a design that Giga, the ministry and the funder can sign off on, and it fixes every decision the build depends on.

| Week | Xcapit | Giga and the ministry |
| --- | --- | --- |
| 1 | Kick-off. Work plan, roles and communication channels agreed with Giga. Inventory of the data flows for the DPIA. Proposal of hosting regions for the resolver | Confirm the pilot country and the connectivity provider. Name the data-protection focal point |
| 2 | Threat model (STRIDE per component, VPR-003). Governor Safe configured on testnet. Draft scope charter: maximum validity, fallback on expiry, appeal response time. Evaluation of proving systems for the aggregation proof | Select 20–50 schools from the Giga map. Name the two institutional signers. Agree the independent reviewer (child-protection NGO or university) |
| 3 | Contract specification (VPR-001) and EAS specification with issuer guidelines (VPR-002). Filtering profiles for primary, secondary and teachers, mapped to ITU COP categories (VPR-006). Draft RFC 8932 privacy statement (VPR-005). ZK statement and circuit specification (VPR-033) | Review the profiles and the scope charter. Review the DPIA draft |
| 4 | DPIA completed (VPR-004). Final scope charters. External auditor booked for weeks 13–15, with a scope covering the contracts, the ZK verifier and circuit, and the resolver configuration. Design review | Sign off the DPIA, the privacy statement v1 and the design. Signers rehearse a test transaction on the testnet Safe |

Deliverables: threat model; contract, EAS and ZK specifications; filtering profiles; scope charters; DPIA; privacy statement v1; testnet Safe with all three signers; confirmed audit slot.

Acceptance: documents merged in this repository; DPIA signed off by Giga's data-protection focal point; design signed off by Giga and the ministry; audit slot confirmed in writing.

## M2 · Registry, resolver and attestations · weeks 5–10 · 35%

Deliverables:
- contracts deployed and verified on OP Sepolia, with scopes created under the governor Safe and the anchor bound to the governor (VPR-009, VPR-010, VPR-011);
- EAS schemas registered (VPR-012) and attestation commands for operator and reviewer (VPR-013);
- policy publisher and resolver synchronisation from the registry (VPR-014, VPR-015);
- resolver pair live with DNSSEC, DoT/DoH and RPZ, hardened against bypass (VPR-019);
- metrics exporter (VPR-016) and block and appeal page (VPR-017);
- reviewer test kit (VPR-018);
- policy v1 signed and published;
- 20–50 schools onboarded in waves from week 8, each with a deployment and an independent test attestation;
- DPG application submitted (VPR-025).

Acceptance: at least 20 schools hold a valid `VPR.IndependentTest.v1` signed by the reviewer; policy v1 published with signatures; DPG application submitted.

The pilot records start on OP Sepolia. Filtering does not depend on the network, so schools are protected from the day they are onboarded. The records move to OP Mainnet once the audit is closed (M3).

## M3 · Metrics, dashboard and audit · weeks 8–16 · 30%

Deliverables:
- daily aggregation, publication and root anchoring from the first attested school onwards (VPR-020);
- public dashboard showing policies with their history, attested schools and daily metrics with a verification button (VPR-021);
- NIST SP 800-81r3 compliance matrix and UK Safer Internet Centre checklist (VPR-022, VPR-023), with `VPR.Conformance.v1` attestations;
- pre-audit hardening, including Merkle domain separation (VPR-027), static analysis and invariant tests (VPR-040, VPR-042);
- contract freeze at the end of week 12, external audit in weeks 13–15, fixes and re-check (VPR-024);
- deployment to OP Mainnet in week 16, with scopes, the policy in force and the attestations re-published there;
- impact report and playbook for new countries (VPR-026).

Acceptance: a party outside the project recomputes published roots; the audit report is public with no open high-severity findings; the impact report is validated by Giga.

## M4 · Zero-knowledge proofs of aggregation · weeks 5–16 · 25%

Goal: each daily release comes with a proof that it is the correct k-suppressed aggregation of a committed event log, and that every event's category belongs to the policy in force. The operator can then no longer alter the figures between the log and the publication (white paper, §5.4 and §11). The event log itself stays private, because it contains the counts below *k*.

| Weeks | Work |
| --- | --- |
| 5–7 | Proving system chosen from the M1 evaluation (zkVM or dedicated circuit). Event-log commitment format. Reference implementation of the statement in Python, used as the test oracle (VPR-034) |
| 8–11 | Circuit or zkVM program for counting, k-suppression and category membership, with tests against the oracle and benchmarks on commodity hardware (VPR-030, VPR-036) |
| 10–12 | On-chain verifier and an anchoring function that accepts a root only together with a valid proof, frozen with the other contracts at the end of week 12 (VPR-035) |
| 12–14 | Prover integrated in the daily job; proofs published with each release; `vpr verify-proof` for independent verification (VPR-037) |
| 13–16 | Audit of the circuit and verifier within the external audit; proofs live on OP Mainnet from week 16 |

Acceptance: every daily release from week 14 to the end of the pilot carries a proof accepted by the on-chain verifier (on OP Sepolia until the move to OP Mainnet); proving time and cost are documented; the audit covers the circuit and the verifier.

The proof binds the published figures to the committed log. It does not prove that the log is complete. That link still rests on the reviewer's tests and the audit, and further work on trusted execution is described in the white paper (§11).

## Schedule risks

- **Audit capacity.** External auditors are often booked weeks ahead, and few review circuits. The slot is reserved in week 4 with the ZK scope included, and all contracts are frozen at the end of week 12.
- **Circuit audit.** If the review of the circuit and verifier is not closed by week 16, M4 is accepted on the testnet verifier and on independent verification with `vpr verify-proof`, and the verifier moves to OP Mainnet once the audit closes. The other contracts are not held back.
- **Proving cost.** If proving a full day exceeds the daily budget on commodity hardware, the fallback is to prove per school and aggregate the proofs. The benchmarks in weeks 8–11 decide this before the freeze.
- **Network conditions.** Satellite and congested rural links, and providers that cannot redirect DNS or block external resolvers, can delay onboarding or weaken protection. Each school's latency and bypass status are measured at onboarding, and schools whose provider cannot enforce DNS are reported as not protected rather than attested ([ARCHITECTURE](ARCHITECTURE.md#deployment-conditions)).
- **School onboarding.** Onboarding depends on the ministry and the connectivity provider. Schools are onboarded in waves from week 8, so that a delay does not hold up the whole cohort.
- **Data window.** Four months leave six to eight weeks of metrics for the impact report. Longer-term figures are reported after the pilot, from the same public datasets.

## After the pilot

Operating options, cost per school and the handover package are described in [SUSTAINABILITY.md](SUSTAINABILITY.md).


Scale to more countries through Giga; recertify every policy cycle; community governance of the schemas; explore an EAS community standard for the schemas; evaluate trusted execution (VPR-032) and verifiable differential privacy (VPR-031).
