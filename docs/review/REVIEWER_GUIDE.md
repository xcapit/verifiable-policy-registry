# Reviewer guide

*CC BY 4.0 · For an external reviewer or auditor. This guide is not a review; it sets out the scope, how to reproduce every result, and where the evidence for each question is.*

## 1. What to review

- **Commit.** A release tag (the latest is listed in the [changelog](../../CHANGELOG.md)). Record its full commit hash in your report.
- **In scope.**
  - contracts: `contracts/src/` (`VerifiablePolicyRegistry`, `MetricsAnchor`, `IssuerRoleResolver`);
  - tools and toolkit: `tools/vpr/`;
  - schemas: `schemas/`;
  - demonstrator: `examples/e2e/`, `contracts/scripts/e2e.js`;
  - specifications and claims: `docs/INTERFACES.md`, `docs/security/`, `docs/privacy/`, `docs/CLAIMS_AND_EVIDENCE.md`.
- **Out of scope**, because it does not exist yet:
  - a running resolver, and the sync daemon, exporter, relayer and dashboard;
  - any ZK circuit or verifier;
  - any public deployment or registered EAS schema;
  - any real data.

## 2. Reproduce

```bash
git checkout <tag>
cd contracts && npm ci
npx hardhat test                                   # unit and EAS integration tests
npx hardhat coverage                               # coverage (CI gate: 100 % lines, 98 % branches)
FOUNDRY_PROFILE=ci forge test                      # fuzz and invariant suites (Foundry 1.3.5)
python3 scripts/mutation_check.py                  # targeted mutation check, in a temporary copy
python3 scripts/symbolic_check.py                  # Halmos symbolic checks (pip install halmos==0.3.3)
slither . --compile-force-framework hardhat --filter-paths "node_modules|test-foundry"   # Slither 0.11.3
cd ..
pip install -e tools && (cd tools && python -m pytest -q)    # tools, toolkit, privacy and CLI tests
E2E_OUT=out ./examples/e2e/run.sh                              # demonstrator; writes out/evidence-manifest.json
python tools/bench/bench_merkle.py                             # release benchmark
(cd contracts && BENCH_CHECK=1 npx hardhat run scripts/bench-workload.js)   # one-year workload gas, checked
```

Prerequisites: Node.js 20 or later, Python 3.10 or later (Halmos 0.3.3 tested with 3.12), Foundry 1.3.5. No secrets, paid services or network access are needed beyond package installation. CI runs the same commands on every push; [CONTRACT_ASSURANCE.md](../security/CONTRACT_ASSURANCE.md) records the expected results.

## 3. Evidence index

| Topic | Start here |
| --- | --- |
| What is and is not claimed | [CLAIMS_AND_EVIDENCE.md](../CLAIMS_AND_EVIDENCE.md) |
| Normative formats and ABIs | [INTERFACES.md](../INTERFACES.md) |
| Contract assurance (static analysis, invariants, symbolic checks, mutation, coverage, gas, OP Stack time) | [security/CONTRACT_ASSURANCE.md](../security/CONTRACT_ASSURANCE.md) |
| Encodings, commitments, designed ZK relation, risks | [security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md](../security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md) |
| Threats | [security/THREAT_MODEL.md](../security/THREAT_MODEL.md) |
| Privacy and re-identification | [privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md) |
| Governance and recourse | [GOVERNANCE.md](../GOVERNANCE.md) |
| Measurements | [benchmarks/BENCHMARKS.md](../benchmarks/BENCHMARKS.md) |
| Design decisions | [adr/](../adr/README.md) |

## 4. Known limitations

- **ZK.** The proof of aggregation is designed only; the proving system is not chosen.
- **DNS stage.** The demonstrator evaluates the compiled zone; it does not resolve queries. No-logging is asserted by configuration, not tested.
- **Log completeness.** Completeness and truthfulness of the event log rest on the reviewer's tests and on audit.
- **EAS.** Issuer roles are enforced at issuance by `IssuerRoleResolver`; the schemas are not registered on a public network.
- **Release policy.** The threshold, minimum cohort and category tiers need pilot data and the DPIA.
- **Dataset licence.** Undeclared (VPR-059).

## 5. Questions and where the evidence is

| # | Question | Evidence to examine |
| --- | --- | --- |
| 1 | Are the properties that rest on cryptography and on the ledger correctly separated from those that rest on institutions? | White paper §3.3 and §6.1; claims ledger C01–C21 |
| 2 | Do the contracts enforce what INTERFACES specifies, and do the invariant suites and the symbolic checks check it (are the predicates of `test-foundry/symbolic/` faithful to INTERFACES, and are the bounds adequate)? | CONTRACT_ASSURANCE §4–§5; INTERFACES I2 and I7 |
| 3 | Are the OP Stack time, ordering and finality assumptions stated correctly and handled? | CONTRACT_ASSURANCE §9; threat model T26–T29; manifest `finality` |
| 4 | Is the Merkle encoding unambiguous, and is `verifyRow` sound against internal-node and cross-day substitution? | White paper §5.3; crypto evidence §3 |
| 5 | Is the ZK relation sound, including hiding of the log commitment and binding of categories to the policy? | Crypto evidence §5–§7; ADR-0010 |
| 6 | What can canary events establish? | Crypto evidence §8; VPR-038 |
| 7 | Is the restricted-list commitment appropriate, and what does it prove? | Crypto evidence §2 and §9; claim C35 |
| 8 | Is small-cell suppression at *k* = 10 adequate, and can published data single out individuals when joined with public data? | Privacy analysis §3–§6; `tools/tests/test_privacy.py` |
| 9 | Do expiry, appeals and the governor design protect against censorship, and where do they not? | Governance; threat model T15–T17 and T34; claim C07 |
| 10 | Does the system create a new surveillance capability? | Privacy analysis §1; threat model T01 and T09; privacy statement |

## 6. What a review should produce

- the exact commit reviewed and the reviewer's identity, qualifications and declared conflicts of interest;
- for each question, a finding with severity, evidence (file and line) and a recommendation;
- any claim in the ledger the reviewer considers wrong or unsupported;
- the reviewer's own reproduction results;
- a statement of scope and exclusions, signed by the reviewer.
