# v0.3 baseline and gap analysis

*CC BY 4.0 · Written before any v0.3 change, on branch `feat/v0.3-esp-giga-readiness`. It is the reference against which v0.3 claims are checked.*

## 1. Baseline inspected

| Item | Value |
| --- | --- |
| Baseline commit | `7e5b8e2` on `main`, tagged `v0.2.0` (GitHub pre-release) |
| Earlier tag | `v0.1.0` |
| Branch for this work | `feat/v0.3-esp-giga-readiness` (convention from CONTRIBUTING: `feat/<topic>`) |
| Repository instructions | `CONTRIBUTING.md` (Conventional Commits, DCO sign-off, ADR for interface changes, synthetic `.example` data only), `GOVERNANCE.md`, `SECURITY.md`. No `AGENTS.md` or other agent instructions exist |
| Languages and toolchains | Solidity 0.8.24 with Hardhat 2 and hardhat-toolbox 5 (`contracts/`); Python ≥ 3.10 package `vpr` with pytest (`tools/`); Bash orchestration (`examples/e2e/run.sh`); no Docker configuration |
| CI | `.github/workflows/ci.yml`: jobs `contracts` (Hardhat tests), `tools` (pytest, schema validation of the example policy, CLI smoke test), `e2e` (end-to-end demo), `links` (internal links and anchors) |
| Release process | Version bump PR, changelog entry, annotated tag on `main` after green CI, GitHub pre-release while contracts are unaudited |
| Branch protection | Rulesets on `main`: no force push or deletion; CI required (admins may bypass) |

### Baseline test results

| Command | Where | Result |
| --- | --- | --- |
| `cd tools && python -m pytest -q` | local, Python 3.14.5 | 29 passed |
| `npx hardhat test` (job `contracts`) | CI run 42637673102 on `7e5b8e2`, Node.js 20 | 16 passing |
| `./examples/e2e/run.sh` (job `e2e`) | same CI run | "End-to-end demo passed." |
| `python .github/scripts/check_links.py` (job `links`) | same CI run | 29 Markdown files, 0 problems |

There are no failing baseline tests. Any failure after this point is introduced by v0.3.

**Deviation on local runs.** Hardhat tests and the demo compile contracts. The repository owner's standing rule is that agents do not build locally, so the authoritative results for those jobs come from CI on the PR. Python tests are run locally and in CI.

## 2. Requirement mapping

Status words: **Implemented and verified in v0.2**, **Present but incomplete or unverified**, **Not implemented**, **Not applicable**, **Blocked**.

### P0.1 · Baseline and claim inventory

| Requirement | v0.2 status | Note |
| --- | --- | --- |
| Baseline and gap analysis | Not implemented | This document |
| Claims-and-evidence ledger | Not implemented | Claims are spread over README, white paper and DPG.md without per-claim evidence links |

### P0.2 · ZK and cryptographic evidence

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Canonical policy serialisation and content hash | Implemented and verified | `tools/vpr/policy.py` (`canonical_json`, `content_hash`), tests in `tools/tests/test_policy.py` |
| Merkle leaf/node construction with domain separation, day binding, length prefixes | Implemented and verified | `MetricsAnchor.leafHash/verifyRow`, `tools/vpr/metrics.py`, `tools/vpr/merkle.py`; shared vector tested in Solidity and Python |
| Odd-node, ordering, duplicate and empty rules | Implemented; partly documented | Odd node promoted; rows sorted; duplicates rejected; empty release rejected. Not yet written down in one place |
| Binding of category set and validity to the on-chain version | Present but incomplete | Categories and `valid_days` are inside the hashed document, but nothing checks that the on-chain `validity` equals the document's `valid_days`, or that the resolver's zone derives from the categories |
| Event-log commitment | Not implemented | Events are aggregated directly; no commitment to the log exists |
| ZK relation, proving system, verifier | Not implemented | Sketch in white paper §11; roadmap M4 (testnet, phase 1) |
| Canary events | Not implemented | Mentioned in white paper §11.2 and VPR-038 |
| Single authoritative crypto specification | Not implemented | Content split across INTERFACES I1/I6/I7 and white paper §5.3/§11 |

### P0.3 · Privacy, threat and child safety

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Threat model document | Present but incomplete | White paper §6 (adversaries A1–A10), DO_NO_HARM H1–H8; no asset/trust-boundary/STRIDE register (VPR-003) |
| Privacy and re-identification analysis | Present but incomplete | White paper §5.2 limits; no data inventory or public-field analysis |
| Data inventory and retention table | Not implemented | Partial in white paper Appendix A |
| Policy governance with recourse and emergency path | Present but incomplete | `docs/GOVERNANCE.md` (policy governance, reason codes); escalation and emergency unblock exist only as charter items in the roadmap |
| Privacy regression tests | Present but incomplete | Tests for suppression and for the absence of the suppressed-cell count in the summary; no tests on CLI output, errors or demo artefacts |
| Legal compliance claims | Not applicable | The repository makes none; applicable law is external and jurisdiction-specific |

### P0.4 · Reusable verification toolkit

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Hashing, Merkle, dataset verification in a library | Present but incomplete | `vpr` package; the API names are school-specific (`school_id`), no documented stable API |
| CLI with machine-readable output and exit codes | Present but incomplete | Exit codes exist for `verify-root`; no JSON output mode, no row-proof commands |
| Second, non-school use case | Not implemented | — |
| Integration guide and compatibility policy | Not implemented | — |
| Cross-implementation fixtures | Implemented and verified | Shared Merkle vector |

### P0.5 · Giga pilot-readiness package

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Operating model, cost model, deployment conditions | Present but incomplete | `docs/SUSTAINABILITY.md`, ARCHITECTURE "Deployment conditions" and "Integration with Giga" |
| Pilot readiness, measurement, incident runbook, localisation, open questions | Not implemented | — |
| Any Giga commitment | Not applicable | None exists; none may be implied |

### P0.6 · ESP package

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Public-goods case, scope, reuse, risks, evidence index | Not implemented | README "What other builders can reuse" and ROADMAP reusable outputs are the only material |
| Budget and team commitments | Blocked | Require maintainer input; template only |

### P0.7 · DPG evidence matrix

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Nine-indicator matrix with evidence | Present but incomplete | `docs/DPG.md` self-assessment against v1.1.6 |
| Current standard version | Present but incomplete | The DPGA CHANGELOG lists **v1.1.7 (2025-06-26)**, which adds AI-system components, requires fully open-licensed content and data, and edits indicator 8; `standard.md` in the repository still shows 1.1.4 text and the latest tag is v1.1.6. The matrix must cite all of this |

### P1 · Demonstrable readiness

| Requirement | v0.2 status | Evidence or gap |
| --- | --- | --- |
| Policy → zone → aggregation → root → on-chain → proof | Implemented and verified | `examples/e2e/run.sh`, CI job `e2e` |
| Exercise allowed and blocked domains | Not implemented | The zone is compiled but never queried |
| Real DNS resolver in the demo | Not implemented | Reference Unbound fragment only |
| Expiry and appeal paths in the demo | Present but incomplete | Appeal filing exercised; expiry and rejection not |
| Rejection of wrong policy hash and wrong root | Not implemented | Tampered row and wrong day are rejected |
| Evidence manifest | Not implemented | — |
| Explicit ZK boundary | Not implemented | — |
| Benchmarks | Not implemented | — |
| Reviewer guide mapped to the 14 questions | Not implemented | — |

## 3. Plan and deviations

**Order of work.** First this analysis. Then, in parallel: (a) the Giga, ESP and DPG packages, which are documentation; (b) the cryptographic evidence pack, the threat model and the privacy analysis. Next come the toolkit generalisation with a second use case and privacy regression tests, then the demonstrator with its evidence manifest and benchmarks. Last are the claims ledger, the reviewer guide, document reconciliation, the implementation report and the PR.

**Deviations from the brief, with reasons.**

1. **No real resolver container in v0.3.** The demo evaluates domains against the compiled zone with an RPZ evaluator (`vpr evaluate`). That is labelled a zone evaluation, not DNS resolution. A pinned Unbound container is recorded as *Planned* (M2, VPR-019): it cannot be validated in this iteration without local builds, and an unvalidated container would itself be an unsupported claim.
2. **ZK remains Designed.** v0.3 delivers a normative relation specification, the encodings, test vectors for the non-ZK primitives, a proving-system decision record and a risk register. It delivers no proof path, as the brief requires.
3. **Policy governance stays in `docs/GOVERNANCE.md`.** The file already is the policy-governance document, and schemas and INTERFACES link to its anchors. It is extended rather than duplicated as `POLICY_GOVERNANCE.md`, and the gap analysis records the mapping.
4. **The eight-week plan is compressed into one iteration.** Work that needs partners, pilot data, an auditor or funding is marked *Blocked* or *Planned* with an owner; nothing is simulated to fill the gap.
5. **Hardhat runs only in CI**, as explained in §1.
