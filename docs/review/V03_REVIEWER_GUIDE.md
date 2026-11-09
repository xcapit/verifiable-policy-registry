# v0.3 reviewer guide

*CC BY 4.0 · For a qualified, independent reviewer. **This preparation is not an audit and not an independent review**; it is meant to make an independent review possible. Nothing here pre-answers the questions.*

## 1. What to review

- **Commit.** The head commit of the v0.3 pull request (`feat/v0.3-esp-giga-readiness`). Record its full hash in your report. The v0.2 baseline is tag `v0.2.0` (`7e5b8e2`).
- **In scope.**
  - contracts: `contracts/src/`;
  - tools and toolkit: `tools/vpr/`;
  - schemas: `schemas/`;
  - demonstrator: `examples/e2e/`, `contracts/scripts/e2e.js`;
  - specifications and claims: `docs/security/`, `docs/privacy/`, `docs/CLAIMS_AND_EVIDENCE.md`, `docs/INTERFACES.md`;
  - plans: `docs/ROADMAP.md`, `docs/giga/`, `docs/esp/`, `docs/DPG_EVIDENCE_MATRIX.md`.
- **Out of scope**, because it does not exist yet:
  - a running resolver;
  - the sync daemon, exporter, relayer and dashboard;
  - any ZK circuit or verifier;
  - any public deployment;
  - any real data.

## 2. Commands

```bash
git checkout <commit>
cd contracts && npm ci && npx hardhat test && cd ..          # contract tests
pip install -e tools && (cd tools && python -m pytest -q)    # tools, toolkit, privacy and CLI tests
E2E_OUT=out ./examples/e2e/run.sh                              # demonstrator; writes out/evidence-manifest.json
python tools/bench/bench_merkle.py                             # release benchmark
python .github/scripts/check_links.py                          # documentation links
```

Prerequisites: Node.js 20 or later, Python 3.10 or later. No secrets, no paid services and no network access are needed beyond package installation. CI runs the same commands on every push.

## 3. Evidence index

| Topic | Start here |
| --- | --- |
| What is and is not claimed | [CLAIMS_AND_EVIDENCE.md](../CLAIMS_AND_EVIDENCE.md) |
| Baseline and gaps | [V03_BASELINE_AND_GAP_ANALYSIS.md](../V03_BASELINE_AND_GAP_ANALYSIS.md) |
| Encodings, commitments, designed ZK relation, risks | [security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md) |
| Threats | [security/THREAT_MODEL.md](../security/THREAT_MODEL.md) |
| Privacy and re-identification | [privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md) |
| Governance and recourse | [GOVERNANCE.md](../GOVERNANCE.md) |
| Measurements | [benchmarks/BENCHMARKS.md](../benchmarks/BENCHMARKS.md) |
| Plan and gates | [ROADMAP.md](../ROADMAP.md) |
| Pilot proposal | [giga/PILOT_READINESS.md](../giga/PILOT_READINESS.md) |
| Ecosystem case | [esp/APPLICATION_EVIDENCE_INDEX.md](../esp/APPLICATION_EVIDENCE_INDEX.md) |
| DPG self-assessment | [DPG_EVIDENCE_MATRIX.md](../DPG_EVIDENCE_MATRIX.md) |

## 4. Known limitations and unresolved items

- **ZK.** The proof of aggregation is Designed only. The proving-system decision is open.
- **DNS stage.** The demo evaluates the compiled zone; it does not resolve queries. No-logging is asserted by configuration, not tested.
- **Log completeness.** Completeness and truthfulness of the event log rest on institutional controls.
- **Roles in EAS.** Issuer roles are recorded on-chain and enforced at issuance by `IssuerRoleResolver` (added after v0.3.0); the schemas are not yet registered on a public network.
- **Scope discovery.** It relies on a deployment manifest that is not yet specified (VPR-049).
- **Release policy.** The threshold, minimum cohort and category tiers need pilot data and the DPIA.
- **Dataset licence.** The licence of published datasets is undeclared (VPR-059, blocked on a maintainer decision).
- **Partner inputs.** Costs, partners, signers and the pilot country are unknown.

## 5. The 14 review questions and where the evidence is

| # | Question | Evidence to examine |
| --- | --- | --- |
| 1 | Are cryptographic and institutional properties correctly separated? | White paper §3.3 and §6.1; claims ledger C01–C21; crypto evidence §12 |
| 2 | Is the ZK relation sound, including hiding of the log commitment and binding of categories to the policy? | Crypto evidence §5–§7; ADR-0010 |
| 3 | What can canary events establish? | Crypto evidence §8; VPR-038 |
| 4 | Are the L2 assumptions stated and proportionate? | Threat model T26–T29; white paper §6 |
| 5 | Is the restricted-list hash appropriate, and what does it prove? | Crypto evidence §2 and §9; claims C35 |
| 6 | Is small-cell suppression at *k* = 10 adequate? | Privacy analysis §3–§5; `tools/tests/test_privacy.py` |
| 7 | Can published data single out individuals when joined with public data? | Privacy analysis §4 and §6 |
| 8 | Do expiry, appeals and the 2-of-3 governor protect against censorship? | Governance; threat model T15–T17 and T34; claims C07 |
| 9 | Does the system create a new surveillance capability? | Privacy analysis §1; threat model T01 and T09; privacy statement |
| 10 | Is the 16-week phase 1 feasible? | Roadmap (gates, risks); ESP scope; Giga readiness |
| 11 | Are acceptance criteria objective? | Roadmap gates; backlog; ESP milestones |
| 12 | Is this a reusable public good for Ethereum builders? | ESP package; integration guide; `examples/public-service`; ADR-0009 |
| 13 | Is the pilot proposal operationally credible for Giga? | `docs/giga/`; sustainability; cost model template |
| 14 | What is the status of each DPG indicator? | DPG evidence matrix |

## 6. What an independent review should produce

- the exact commit reviewed and the reviewer's identity, qualifications and declared conflicts of interest;
- for each of the 14 questions, a finding with severity, evidence (file and line) and a recommendation;
- any claim in the ledger the reviewer considers wrong or unsupported;
- the reviewer's own reproduction results;
- a statement of scope and exclusions, signed by the reviewer.
