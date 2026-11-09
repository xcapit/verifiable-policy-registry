# Pilot readiness

*CC BY 4.0 · Proposal package for a school pilot · v0.3 preparation*

> **Status of this package.** This is a proposal prepared by the project team. No commitment, letter of interest, endorsement, approval or deployment exists from Giga, UNICEF, ITU, any ministry, any connectivity provider or any school. Every decision that requires a partner is listed in [OPEN_QUESTIONS_FOR_GIGA.md](OPEN_QUESTIONS_FOR_GIGA.md) and remains open until that partner confirms it in writing.

## Purpose

This package describes how the Verifiable Policy Registry (VPR) could be piloted in schools connected through Giga, written for programme, education and data-protection staff rather than for blockchain engineers. VPR is a DNS-based filter (it decides, before a page loads, whether a website's name is allowed) combined with a **public record** in which every filtering rule, every change, every appeal and a daily summary of how many threats were blocked are published so that anyone can check them. The public record is a shared ledger that no single party can rewrite; schools, teachers and ministry staff never need to use it directly.

## The package

| Document | Question it answers |
| --- | --- |
| [PILOT_ARCHITECTURE.md](PILOT_ARCHITECTURE.md) | What runs where, and what happens when the connection or a component fails |
| [OPERATING_MODEL.md](OPERATING_MODEL.md) | Who does what, who maintains it, who pays, and what happens after the pilot |
| [MEASUREMENT_AND_EVALUATION.md](MEASUREMENT_AND_EVALUATION.md) | How success is measured without collecting anyone's browsing history |
| [INCIDENT_AND_APPEALS_RUNBOOK.md](INCIDENT_AND_APPEALS_RUNBOOK.md) | What to do when a site is wrongly blocked, a threat is missed, or something breaks |
| [COST_MODEL_TEMPLATE.md](COST_MODEL_TEMPLATE.md) | How to compute the cost per school, with every unknown input marked |
| [LOCALISATION_AND_ACCESSIBILITY.md](LOCALISATION_AND_ACCESSIBILITY.md) | Languages, accessibility and low-literacy considerations |
| [OPEN_QUESTIONS_FOR_GIGA.md](OPEN_QUESTIONS_FOR_GIGA.md) | Decisions that only Giga or an implementing partner can take |

## Current status of the components

| Component | Status | Evidence |
| --- | --- | --- |
| Policy registry and daily-summary anchor (contracts) | Implemented, not audited | `contracts/`, CI job `contracts` |
| Policy validation, filter-zone compilation, aggregation tools | Implemented | `tools/`, CI job `tools` |
| End-to-end flow on a local test network with synthetic data | Demonstrated | `examples/e2e/run.sh`, CI job `e2e` |
| Checking test domains against the compiled filter zone | Implemented in v0.3 as a zone evaluation, not DNS resolution | `vpr evaluate` |
| Production DNS resolver for schools | Designed (reference configuration only) | `deploy/unbound/rpz.conf`, roadmap M2 |
| Block page and appeal relayer, Spanish and Portuguese | Planned (VPR-017) | [../BACKLOG.md](../BACKLOG.md) |
| Independent reviewer test kit | Planned (VPR-018) | [../BACKLOG.md](../BACKLOG.md) |
| Zero-knowledge proofs of the daily summary | Designed; reference implementation on a test network is planned (M4) | [../ROADMAP.md](../ROADMAP.md) |
| External audit | Planned (M3, weeks 13–15) | [../ROADMAP.md](../ROADMAP.md) |

Claims and their evidence are tracked in [../CLAIMS_AND_EVIDENCE.md](../CLAIMS_AND_EVIDENCE.md).

## Stages

The pilot follows the two-phase plan in [../ROADMAP.md](../ROADMAP.md), preceded by a synthetic pre-pilot.

| Stage | When | Schools | Data |
| --- | --- | --- | --- |
| 0 · Synthetic pre-pilot | Weeks 1–6 | None | Synthetic policy, synthetic domains, synthetic event counts |
| 1 · Alpha | Weeks 8–16 (phase 1) | 2–5 schools | Real DNS traffic processed in memory; only daily aggregate counts leave the resolver |
| 2 · Cohort | Phase 2, only if gates are met | 20–50 schools | Same as alpha |

### Stage 0 · Synthetic pre-pilot

Before any school is connected, the full flow runs end to end on a public test network with synthetic data only: a synthetic policy is published, compiled into a filter zone and checked against a list of synthetic allowed and blocked domains; synthetic events are aggregated with small-cell suppression; the daily summary is anchored in the public record and verified independently; an appeal is filed and resolved; a policy is allowed to expire to confirm the fallback. Ministry and Giga staff can watch this run and repeat it from the instructions in the repository. Nothing in Stage 0 touches a school network or a child.

**Exit criteria for Stage 0.** All steps pass on the test network; the reviewer confirms that no output contains queried domain names, IP addresses or device identifiers; the scope charter, DPIA and privacy statement are signed (Gate A in the roadmap).

### Entry gates for the alpha (Stage 1)

All of the following must be true before the first school is connected:

1. Gate A met: DPIA, privacy statement (RFC 8932 format) and scope charter signed by the data-protection focal point and the governing institutions.
2. The two institutional signers and the independent reviewer are named and have rehearsed a policy change on the test network.
3. The connectivity provider has confirmed in writing that it can direct school DNS to the resolver and block external resolvers for the alpha schools ([../ARCHITECTURE.md](../ARCHITECTURE.md#deployment-conditions)).
4. The block page with an appeal route exists at least in the main language of the pilot country.
5. The reviewer test kit can run from a school network.
6. A rollback has been rehearsed: the school's DNS setting can be returned to its previous state within one working day.

### Exit gates for the alpha (Gate B and Gate C)

- Gate B (week 10): at least two alpha schools hold a valid independent test attestation, bypass tests pass, and no personal data appears in any export.
- Gate C (week 16): the registry and anchor are audited, with no open high-severity finding, before they are used on the main public network.

Phase 2 (Stage 2) is proposed only if both gates are met and the evaluation in [MEASUREMENT_AND_EVALUATION.md](MEASUREMENT_AND_EVALUATION.md) supports it.

### Stop conditions

The pilot in a school, or the whole pilot, stops if any of the following occurs:

- personal data (a queried domain tied to a device, an IP address, a name) is found in any published dataset, log or public record;
- an over-block of educational or health content is not corrected within the agreed response time and the governing institutions cannot agree on a correction;
- the reviewer cannot test a school for two consecutive cycles;
- a policy is changed without the required signatures, or a signer key is believed compromised and cannot be rotated;
- the ministry, the school community or Giga asks to stop.

### Rollback

Rollback means returning the school's DNS to its previous configuration through the connectivity provider. It does not delete anything from the public record: policy versions, appeals and summaries already published remain readable, which is intended. The operator records the rollback and its reason in the incident log, and the reviewer's attestation for that school is revoked so that dashboards stop showing it as protected.

## What the pilot will not do

- It will not collect individual browsing histories, for evaluation or any other purpose.
- It will not install software on student or teacher devices.
- It will not filter at the level of individual web pages (DNS works on domain names).
- It will not be extended to ISP-wide or national filtering.
- It will not publish restricted lists such as the IWF list; only a cryptographic fingerprint of such a list is public.

Related analyses: [../security/THREAT_MODEL.md](../security/THREAT_MODEL.md), [../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md), [../DO_NO_HARM.md](../DO_NO_HARM.md), [../DPG_EVIDENCE_MATRIX.md](../DPG_EVIDENCE_MATRIX.md).
