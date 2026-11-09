# Roadmap

*CC BY 4.0 · The plan has two phases. **Phase 1** is four months from the start of funding: one month of design and sign-off, then three months of work. It delivers a reusable, testnet reference implementation, a zero-knowledge aggregation prototype with benchmarks, a controlled alpha in a few schools and an audited registry. **Phase 2** scales the deployment and takes the zero-knowledge verifier to mainnet. It starts only if the phase 1 gates are met. Payment shares are indicative.*

<p align="center"><img src="figures/roadmap.svg" alt="Sixteen-week phase 1 roadmap with gates" width="100%"></p>

## Why two phases

A single 16-week plan that onboards 20–50 schools, runs an audit, deploys to mainnet and builds and audits a new zero-knowledge system leaves no margin. Several of its steps also depend on decisions the team does not control: country approval, providers, and auditor availability for circuits. Phase 1 therefore commits only to outcomes the team can deliver and others can verify. These are open specifications, reference code, test vectors, benchmarks, an alpha with real measurements and an audited registry. Everything that depends on scale or on a second audit is gated into phase 2. The reviewer tests, the privacy work, the appeal safeguards, resolver hardening and the audit of the registry contracts are not cut.

## Phase 1 at a glance

| Milestone | Weeks | Share | Ends with | Reusable outputs |
| --- | --- | --- | --- | --- |
| M0 · Proof of concept | before funding | — | This repository (done) | Contracts, `vpr` tools, schemas, end-to-end demo |
| M1 · Design and sign-off | 1–4 | 15% | **Gate A**: specifications, DPIA and scope charter signed off | Normative contract, EAS and ZK specifications; deployment manifest format; threat model |
| M2 · Testnet reference implementation and alpha | 5–10 | 35% | **Gate B**: alpha running in 2–5 schools on OP Sepolia | Deployment scripts, sync daemon, exporter, relayer, block page (es/pt), reviewer kit, hardened resolver profile |
| M3 · Metrics, audit and registry on mainnet | 9–16 | 25% | **Gate C**: audited registry and anchor on OP Mainnet | Dashboard, compliance matrices, audit report, operations runbooks |
| M4 · Zero-knowledge aggregation, reference implementation | 5–16 | 25% | Proofs verified on OP Sepolia for every alpha release from week 14 | Circuit or zkVM program, testnet verifier, `vpr verify-proof`, test vectors, benchmarks |

Every milestone produces artefacts that are useful outside this pilot: other networks with an accountable governor can deploy the same registry, schemas, tools and verifier ([README](../README.md#what-other-builders-can-reuse)).

## M0 · Proof of concept · done

- [x] `VerifiablePolicyRegistry` with versions, reasons, mandatory expiry, appeals by document hash with reasoned resolutions, on-chain issuer roles and governor rotation
- [x] `MetricsAnchor` with daily roots anchored once by the publisher and corrected only publicly by the governor, a publisher appointed by the governor and on-chain row verification
- [x] Python tooling: full policy validation and hashing, fail-closed RPZ compilation, aggregation with small-cell suppression, Merkle proofs, CLI
- [x] EAS schema definitions with separate issuer roles
- [x] End-to-end demo and CI
- [x] White paper, architecture, interfaces, decision records, governance, privacy statement draft, sustainability model

## M1 · Design and sign-off · weeks 1–4 · 15%

| Week | Xcapit | Giga and the ministry |
| --- | --- | --- |
| 1 | Kick-off. Work plan, roles and communication channels agreed with Giga. Data-flow inventory for the DPIA, covering transient processing in the resolver. Proposal of hosting regions. Resolver hosting quotes | Confirm the pilot country and the connectivity provider. Name the data-protection focal point |
| 2 | Threat model (STRIDE per component, VPR-003). Governor Safe configured on testnet. Draft scope charter: maximum validity, fallback on expiry, appeal response time, escalation and emergency unblock, categories that may never be blocked. Evaluation of proving systems | Select 2–5 alpha schools and a provisional list for phase 2. Name the two institutional signers. Agree the independent reviewer |
| 3 | Normative contract and EAS specifications (VPR-001, VPR-002). ZK specification with every public input bound in the statement: chain id, verifier contract, scope, day, policy version and hash, category-set and school-set commitments, *k*, log commitment, output root, format version (VPR-033). Deployment manifest format (VPR-049). Filtering profiles (VPR-006). Draft RFC 8932 statement (VPR-005) | Review the profiles and the scope charter. Review the DPIA draft |
| 4 | DPIA completed (VPR-004). Final scope charters. Auditor booked for weeks 13–15 for the registry and anchor contracts and the resolver configuration. Design review | Sign off the DPIA, the privacy statement v1 and the design. Signers rehearse a test transaction on the testnet Safe |

**Gate A (end of week 4).** Go if the DPIA and scope charter are signed, the alpha schools and signers are named, and the ZK specification is reviewed. If the country or signers are not confirmed, M2 continues on a synthetic testnet deployment and the alpha moves to the first available weeks.

## M2 · Testnet reference implementation and alpha · weeks 5–10 · 35%

Deliverables:
- contracts deployed and verified on OP Sepolia from a deployment manifest; scopes created by the governor Safe; publisher and issuer roles set by the governor (VPR-010, VPR-011, VPR-049);
- EAS schemas registered with a schema resolver that enforces issuer roles (VPR-012) and attestation commands (VPR-013);
- policy publisher and resolver synchronisation from the registry (VPR-014, VPR-015);
- hardened resolver profile, with DNSSEC, DoT/DoH, RPZ, IPv6, certificate lifecycle and bypass blocking (VPR-019);
- metrics exporter (VPR-016), and an appeal relayer with block page in Spanish and Portuguese (VPR-017);
- reviewer test kit (VPR-018);
- alpha in 2–5 schools from week 8, each with a deployment and an independent test attestation; measured latency, availability and cost per school.

**Gate B (end of week 10).** Go if at least two alpha schools hold a valid independent test attestation, bypass tests pass, and no personal data appears in any export (checked by the reviewer). Otherwise M3 runs on the testnet deployment alone, and phase 2 is not proposed until the alpha succeeds.

## M3 · Metrics, audit and registry on mainnet · weeks 9–16 · 25%

Deliverables:
- daily release, publication and anchoring for the alpha schools (VPR-020), with a release policy for small schools defined in the DPIA;
- public dashboard reading the manifest, registry, EAS and anchor (VPR-021);
- NIST SP 800-81r3 compliance matrix and UK Safer Internet Centre checklist (VPR-022, VPR-023);
- static analysis and invariant tests (VPR-040, VPR-042); contract freeze at the end of week 12;
- external audit of the registry, the anchor and the resolver configuration in weeks 13–15, then fixes and a re-check (VPR-024);
- operations runbooks and handover package ([SUSTAINABILITY](SUSTAINABILITY.md));
- DPG application package (VPR-025), submitted once the evidence for indicators 7–9 is signed.

**Gate C (end of week 16).** The registry and anchor are deployed to OP Mainnet only if the audit report is public and has no open high-severity finding; otherwise they stay on OP Sepolia until it does.

## M4 · Zero-knowledge aggregation, reference implementation · weeks 5–16 · 25%

| Weeks | Work |
| --- | --- |
| 5–7 | Proving system chosen from the M1 evaluation. Hiding event-log commitment. Python oracle of the statement (VPR-034) |
| 8–11 | Circuit or zkVM program, tested against the oracle, including negative tests for every bound input: wrong chain, contract, scope, day, policy, category set, school set, *k*, replay, duplicates, empty and fully suppressed days (VPR-030) |
| 10–12 | Benchmarks on commodity hardware for worst-case daily volumes, with a decision on per-school proving (VPR-036) |
| 11–14 | Testnet verifier and anchoring path that accepts a root only with a valid proof (VPR-035) |
| 14–16 | Prover in the daily job for the alpha; proofs published with each release; `vpr verify-proof` (VPR-037) |

Acceptance: every alpha release from week 14 carries a proof accepted by the verifier on OP Sepolia; an outside party verifies one with the CLI; the specification, test vectors and benchmarks are published. The circuit is **not** audited and **not** on mainnet in phase 1.

## Phase 2 · gated follow-on

Phase 2 is proposed only if Gates A–C are met, and it is funded and agreed separately:

- scale from the alpha to a 20–50 school cohort, in waves, with the ministry and provider;
- external audit of the circuit and verifier, then the verifier on OP Mainnet;
- impact report over a full school term, from the public datasets;
- DPG registration, if not already obtained;
- operator handover according to the agreed post-pilot model ([SUSTAINABILITY](SUSTAINABILITY.md)).

## Schedule risks

- **Partner decisions.** Country, provider and signers are outside the team's control. Gate A defines what proceeds without them.
- **Network conditions.** Satellite and congested rural links, and providers that cannot redirect DNS or block external resolvers, can delay the alpha or weaken protection. Each school's latency and bypass status are measured at onboarding. Schools whose provider cannot enforce DNS are reported as not protected rather than attested ([ARCHITECTURE](ARCHITECTURE.md#deployment-conditions)).
- **Audit capacity.** The slot for the registry, the anchor and the resolver configuration is reserved in week 4. The circuit audit is deliberately left to phase 2, where scarce circuit-audit capacity does not hold back the rest.
- **Proving cost.** If proving a full day exceeds the daily budget on commodity hardware, the fallback is one proof per school. The benchmarks decide this by week 12.
- **Data window.** An alpha of a few weeks gives operational evidence (cost, latency, availability), not impact figures. Impact is reported in phase 2.

## After phase 2

Scale to more countries through Giga; recertify every policy cycle; community governance of the schemas; explore an EAS community standard for the schemas; evaluate trusted execution (VPR-032) and verifiable differential privacy (VPR-031). Operating options and costs are in [SUSTAINABILITY.md](SUSTAINABILITY.md).
