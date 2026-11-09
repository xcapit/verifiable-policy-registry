# v0.3 implementation report

*CC BY 4.0 · Branch `feat/v0.3-esp-giga-readiness`, based on `v0.2.0` (`7e5b8e2`). Last substantive commit before this report: `de5e039`. CI evidence: run [42644820168](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42644820168) on `de5e039` (contracts, tools, e2e and links all passing). v0.3 is a **release candidate, not released**: no version bump, no tag, and the pull request is left unmerged.*

## 1. Recommendation

**Conditionally ready for external review.** A qualified reviewer can now reproduce every implemented claim, read the specification of every designed one, and see every limitation in one place ([claims ledger](CLAIMS_AND_EVIDENCE.md), [reviewer guide](review/V03_REVIEWER_GUIDE.md)). Four conditions remain before the material is used in a funding application or a Giga conversation:

1. **ZK is Designed, not implemented.** Reviewers must assess a specification, not code.
2. **No licence is declared for published datasets** (VPR-059, a maintainer decision).
3. **Partner inputs are absent:** costs, country, signers and reviewer. The packages mark them as unknown rather than estimating them.
4. **No ESP funding route is currently open.** On 2026-11-09 the official ESP pages listed no active Wishlist, RFP or open round. The package is preparatory and must be matched to a future published opportunity; Office Hours are not a funding application.

## 2. Implemented (code and passing tests)

- Generic verification toolkit (`vpr.toolkit`, API v1), with the unit column `school_id` or `unit_id` (ADR-0009).
- RPZ zone evaluation (`vpr evaluate`), exact rule before wildcard, restricted entries unlabelled.
- CLI commands `prove-row`, `verify-row`, `--json`, and exit codes 0, 1 and 2; errors do not echo suppressed cells or restricted-list entries.
- Second synthetic use case (`examples/public-service/`).
- Privacy regression tests, toolkit tests and CLI tests.
- Release-schema validation in CI for both unit columns.

## 3. Demonstrated (CI, synthetic data, local chain)

`examples/e2e/run.sh`, on a clean CI runner with `npm ci` and `pip install -e tools`, completes the following:

1. Policy hash; zone compilation and evaluation of 4 allowed and 3 blocked domains.
2. School and public-service releases, with roots recomputed and a wrong root rejected.
3. On the local chain: deployment; scope creation, roles and publisher appointed by the governor; a stranger's claim rejected.
4. Policy publication; a modified document does not match.
5. Appeal by hash, rejection with a reason hash, resubmission in round 2.
6. Root anchored and read back; published row accepted; tampered row, other day and wrong root rejected; anchored day not rewritable.
7. Public-service row verified by the same contract.
8. Expiry after 90 days.
9. Explicit stop at "ZK proof: NOT IMPLEMENTED".

It writes `evidence-manifest.json`: commit, versions, chain id 31337, hashes, roots, 16 on-chain stages passed, and gas per operation. CI uploads it as `demo-evidence`.

## 4. Designed or planned

- **Designed:** hiding event-log commitment; ZK relation with all bound inputs; canary checks; on-chain `catRoot` and `unitRoot` (ADR-0010); release-policy framework; scope charter, emergency changes, external recourse.
- **Planned:** pinned resolver container (VPR-055); deployment manifest (VPR-049); EAS schema resolver enforcing roles (VPR-012); `valid_days` and version checks (VPR-060); ZK implementation and benchmarks (M4).

## 5. Blocked or unverified

| Item | Status | Needs |
| --- | --- | --- |
| Dataset licence | Blocked | Maintainer decision (ODC-PDDL or CC0) |
| Cost per school | Blocked | Hosting quotes, reviewer rates, testnet gas, pilot measurements |
| Pilot country, provider, signers, reviewer | Blocked | Giga and ministry |
| Release-policy parameters (*N_min*, tiers, delay) | Blocked | DPIA and pilot data |
| Resolver no-logging | Unverified | Running resolver plus audit |
| Proving-system choice | Open decision | M1 week 3 |
| Budget and time commitments in the ESP package | Blocked | Maintainer input |

## 6. Commands run and results

| Command | Environment | Result |
| --- | --- | --- |
| `python -m pytest -q` (tools) | local, Python 3.14.5 (baseline) | 29 passed |
| same | local, after v0.3 changes | 61 passed |
| Hardhat tests (`contracts` job) | CI, Node.js 20 | 16 passing (baseline and v0.3) |
| `examples/e2e/run.sh` (`e2e` job) | CI | passed; 16/16 on-chain stages |
| Link and anchor check (`links` job) | CI | 54 tracked Markdown files, 0 problems |
| Dataset schema validation | CI and local | school and public-service releases valid |
| `pip install -e "tools[dev]"` in a new virtual environment | local | succeeded (after the packaging fix) |
| `python tools/bench/bench_merkle.py` | local and CI | see [benchmarks](benchmarks/BENCHMARKS.md) |

There are no failing or skipped tests. Hardhat and the demonstrator were not run locally: the repository owner's standing rule is that agents do not build locally. CI on a fresh runner is the clean-environment evidence.

## 7. Benchmark summary

- **Release construction**, Python reference implementation: 50 000 rows in 0.50 s on the CI runner (x86_64, Python 3.12) and 0.19 s on the workstation (Apple M5 Pro, Python 3.14).
- **Row verification**: under 80 µs.
- **Gas on the Hardhat EVM**: `commitRoot` 95 886; `publishPolicy` 125 128; `fileAppeal` 118 873; `verifyRow` estimate 30 200 for a 3-step proof.
- **L1 data fees** are not included. No ZK, resolver or school-network measurements exist.

## 8. Security and privacy decisions

- No suppression count is published, and errors do not echo suppressed cells or restricted-list entries. Both are tested.
- The threshold is treated as a parameter for the DPIA, not as a guarantee.
- "Privacy-preserving" is qualified wherever it appears.
- The ZK category binding is enforced through registry state, not prover input (ADR-0010).
- Canaries are documented as sampling, not completeness.
- The restricted-list hash is documented as binding but not hiding, and as evidence of declaration, not of enforcement.

## 9. Bugs found and fixed during v0.3

1. `validate_release` echoed suppressed rows in its error message. That was a privacy leak, and it is now covered by a test.
2. Malformed YAML crashed the CLI with a traceback; it now fails with exit code 2.
3. The editable install broke once `tools/bench` existed, because setuptools found a flat layout with two top-level directories. The `vpr` package is now declared explicitly.
4. The demo's output directory was resolved relative to the working directory after a `cd`; it is now absolute.

## 10. Deviations from the brief

- No resolver container; the DNS stage is a zone evaluation, labelled as such. This keeps any unvalidated infrastructure out of the claims.
- ZK delivered as a specification, a decision record and a risk register, as the brief requires when an implementation is not feasible.
- Policy governance extended in `docs/GOVERNANCE.md` instead of a new `POLICY_GOVERNANCE.md`, to keep existing anchors stable.
- The eight-week plan was compressed into one iteration. Items that need partners, data or funding are marked Blocked or Planned.
- The Giga, ESP and DPG packages use the status vocabulary in the claims ledger and defer partner-dependent decisions to the phase 1 gates.

## 11. Residual risks

- Event-log completeness and truthfulness rest on institutional controls.
- Group inference at small schools remains possible until the release policy is applied.
- Colluding governor majority: visible and temporary, not prevented.
- Contracts are unaudited.
- The DPG Standard version is in flux: the latest tag is v1.1.6 while the CHANGELOG lists v1.1.7.

## 12. Follow-ups

VPR-049, VPR-055, VPR-058, VPR-059, VPR-060, VPR-012, VPR-033 to VPR-038, and the M1 inputs listed in [OPEN_QUESTIONS_FOR_GIGA.md](giga/OPEN_QUESTIONS_FOR_GIGA.md).

## 13. Files changed

New:
- `docs/V03_BASELINE_AND_GAP_ANALYSIS.md`, `docs/CLAIMS_AND_EVIDENCE.md`, `docs/V03_IMPLEMENTATION_REPORT.md`
- `docs/security/`, `docs/privacy/`, `docs/toolkit/`, `docs/benchmarks/`, `docs/review/`
- `docs/giga/` (8 files), `docs/esp/` (5 files), `docs/DPG_EVIDENCE_MATRIX.md`
- ADR-0009 and ADR-0010
- `tools/vpr/toolkit.py`, `tools/bench/bench_merkle.py`
- `tools/tests/test_toolkit.py`, `test_privacy.py`, `test_cli.py`
- `examples/public-service/`

Changed:
- `tools/vpr/cli.py`, `metrics.py`, `policy.py`, `tools/pyproject.toml`
- `examples/e2e/`, `contracts/scripts/e2e.js`, `.github/workflows/ci.yml`, `schemas/dataset.schema.json`
- README, CHANGELOG, white paper (v0.5), ARCHITECTURE, INTERFACES, BACKLOG, GOVERNANCE (policy), PRIVACY_STATEMENT, DO_NO_HARM, SECURITY, DPG.md

Contracts are unchanged since v0.2.0.

## 14. Second review (independent security, privacy and documentation review)

Two independent reviewers (fresh context, read-only) checked the branch after the first documentation pass. Their findings were reproduced before any change. Outcome:

- **Fixed in code, with 33 regression tests (94 Python tests in total):**
  - an exception could cancel a restricted entry (fail-open);
  - empty feeds compiled without protection;
  - an unvalidated block page allowed zone injection;
  - restricted entries leaked through error messages;
  - duplicate YAML keys were accepted;
  - non-identifier units and categories (domains, IP addresses) could reach a release;
  - non-strict dates and counts were accepted;
  - the zone evaluator failed open on records it did not understand;
  - unexpected errors exited with code 1 and a traceback;
  - `verify-row` without a root printed `MATCH`;
  - no threshold check in `verify-root`;
  - non-deterministic zone serials;
  - zone files were world-readable;
  - the reference Unbound fragment did not load (now passes `unbound-checkconf` with deployment files substituted);
  - a vacuous wrong-root check in the demonstrator.
- **Fixed in the ZK specification:**
  - the event count *m* is now private, because publishing it revealed the total of suppressed events;
  - *k* is read from the registry rather than supplied by the prover;
  - the scope is bound in each event leaf;
  - one domain-separation tag per role;
  - the empty-release rule is aligned.
- **Recorded, not changed in this PR** (contract changes would alter the audit target and cannot be compiled locally under the owner's rule): unbounded and back-dated anchor days, no publisher revocation or correction path, single-step governor transfer and uncapped validity, front-running of canonical scope ids, unbounded URIs, and appeal pre-filing. Threats T38–T48; backlog VPR-065 to VPR-069, scheduled before the M3 audit freeze.
- **Documentation corrected:**
  - the ESP scope is narrower than phase 1 and its shares are unallocated;
  - no unfiltered fallback in the pilot;
  - degraded-mode reporting is defined before the dashboard exists;
  - the DPG requirement text is quoted;
  - indicator 6 is downgraded to Credible path;
  - present-tense claims about designed controls are qualified;
  - backlog IDs are made consistent.

