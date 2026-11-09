# Backlog

Issue-ready tasks after the proof of concept. Each has acceptance criteria so it can be implemented spec-first. IDs are stable; reference them in commits (`VPR-012: ...`).

## v0.3 · Readiness for external review

Dependency-aware checklist from the [v0.3 gap analysis](V03_BASELINE_AND_GAP_ANALYSIS.md). Items marked **Done in v0.3** are implemented or written in the v0.3 branch; the others carry their milestone.

| ID | Task | Depends on | Status |
| --- | --- | --- | --- |
| VPR-050 | Baseline, gap analysis and claims-and-evidence ledger | — | **Done in v0.3** |
| VPR-051 | Cryptographic evidence pack: encodings, designed ZK relation, risk register, proving-system decision record | VPR-050 | **Done in v0.3** (decision itself due in M1, VPR-033) |
| VPR-003 | Threat model | VPR-050 | **Done in v0.3** for existing and designed components; review at Gate A |
| VPR-052 | Privacy and re-identification analysis, data inventory, privacy regression tests | VPR-050 | **Done in v0.3**; release-policy parameters need pilot data (DPIA, M1) |
| VPR-053 | Generic verification toolkit, second use case, CLI JSON and exit codes (ADR-0009) | — | **Done in v0.3** |
| VPR-054 | Demonstrator with zone evaluation, expiry, appeal rejection, negative cases and evidence manifest | VPR-053 | **Done in v0.3** |
| VPR-055 | Pinned resolver container in the demonstrator (real DNS queries, no query logging asserted) | VPR-019 | Planned (M2) |
| VPR-056 | Giga pilot-readiness package; ESP package; DPG evidence matrix | VPR-050 | **Done in v0.3** (proposal documents; inputs marked) |
| VPR-057 | Reviewer guide mapped to the 14 review questions | VPR-050–056 | **Done in v0.3** |
| VPR-058 | Registry fields `catRoot` and `unitRoot` (ADR-0010) and ZK verifier anchoring | VPR-033 | Designed; Planned (M4) |
| VPR-059 | Declare the licence of published datasets (ODC-PDDL or CC0) | Maintainer decision | Blocked: maintainer decision |
| VPR-061 | Child-rights and human-rights impact assessment, including a misuse review, with the deploying partner (DPG indicator 9) | Depends on a confirmed partner | Planned (M1–M2); blocked without a partner |
| VPR-062 | Run the demonstrator on a second EVM network and with a second resolver implementation (DPG indicator 4) | VPR-010, VPR-055 | Planned (M2) |
| VPR-063 | Bulk export of on-chain history (versions, appeals, roots) to CSV/JSON (DPG indicator 6) | — | Planned (M3) |
| VPR-064 | Playbook for new countries (charters, profiles, onboarding) | VPR-026 | Planned (M3) |
| VPR-065 | Bind feed contents (hash per feed in `threat_feeds`) and the produced zone (`resolverConfigHash`) to the policy version | Compiler refuses a feed whose hash differs; the attestation carries the zone hash | **Done (pre-audit hardening)** |
| VPR-066 | Anchor hardening: bound `day` to a window around the current date, explicit publisher revocation, governor-gated correction record, length cap on `datasetUri`/`uri`, daily release-or-empty marker | Tests for future/past days, revocation, correction and caps | **Done (pre-audit hardening)** |
| VPR-067 | Registry hardening: two-step `setGovernor`, protocol cap on `maxValidity`, on-chain validation of reason codes | Tests for each; INTERFACES updated | **Done (pre-audit hardening)** |
| VPR-068 | Derive the scope id on-chain from the governor and the scope name, so canonical names cannot be front-run | Front-running test; manifest format updated | **Done (pre-audit hardening)** |
| VPR-069 | Appeal format 3 with a document salt; documentation that rounds are not an escalation count; optional time-out of open appeals | Pre-filing of a guessable document no longer possible; tests | **Done (pre-audit hardening)** |
| VPR-060 | Check of `valid_days` and document version against the on-chain call in tools and dashboard | — | **Done (pre-audit hardening)** |

## M1 · Design and sign-off (weeks 1–4)

See the week-by-week plan in [ROADMAP.md](ROADMAP.md#m1--design-and-sign-off--weeks-14--15). VPR-033 (ZK specification) is also delivered in this milestone.

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-001 | Write `docs/specs/registry.md`: formal spec of both contracts (state, events, errors, invariants) | Every external function documented with pre/post-conditions; invariants listed (versions append-only, expiry mandatory, appeal state machine) |
| VPR-002 | Write `docs/specs/eas.md`: schema fields, issuer roles, revocation rules, validity windows | Matches `schemas/eas-schemas.json`; defines who may issue/revoke each schema |
| VPR-003 | Threat model `docs/security/THREAT_MODEL.md` (STRIDE per component; first version in v0.3, review at Gate A) | Covers registry, governor keys, resolver, exporter, aggregator, block page; each threat mapped to a mitigation or accepted risk |
| VPR-004 | DPIA template `docs/DPIA.md` aligned with UNICEF Policy on Personal Data Protection | Sections for data inventory, necessity, risks, mitigations; reviewed by Giga |
| VPR-005 | Finalise `docs/PRIVACY_STATEMENT.md` (RFC 8932 RPS) | Placeholders resolved; `vpr` command prints its keccak256 |
| VPR-006 | Filtering profiles: `policies/profiles/{primary,secondary,teachers}.yaml` mapped to ITU COP categories | Each validates with `vpr policy-hash`; mapping table in `docs/PROFILES.md` |
| VPR-007 | **Done in 0.2.0.** Validate policy documents against `schemas/policy.schema.json` in `vpr.policy.validate` (`valid_days`, `reason_code`, `profile`, `threat_feeds`, unknown keys) | Invalid example documents fail with a clear message; the shipped example passes; schema and code agree on every field |
| VPR-008 | **Done in 0.2.0.** `vpr restricted-hash <file>` command printing the restricted list commitment | Output equals `policy.restricted_list_hash()`; documented in `docs/INTERFACES.md` |
| VPR-009 | **Done in 0.2.0.** Restrict `MetricsAnchor.configure` so only the registry governor of a scope (or a factory) can configure it | A third party cannot claim a scope; tests cover the front-running case; INTERFACES updated |

## M2 · Testnet reference implementation and alpha (weeks 5–10)

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-010 | Deployment scripts (Hardhat Ignition or scripts/) for OP Sepolia and OP Mainnet | One command deploys both contracts and creates a scope with a Safe as governor; addresses written to `deployments/<network>.json` |
| VPR-011 | Safe integration: script to propose `publishPolicy` as a Safe transaction | Proposal appears in the Safe UI; executed with 2 of 3 signatures on testnet |
| VPR-012 | **Resolver done (pre-audit hardening); registration on a public network remains M2.** EAS schema registration script, with a schema resolver that accepts an attestation only from an address holding the matching role in the registry | Registers the three schemas on OP Sepolia; UIDs stored in `deployments/` |
| VPR-013 | `vpr attest-deployment` and `vpr attest-test` CLI commands (EAS SDK or ethers) | Creates attestations on testnet; reviewer key and operator key are distinct; README documents usage |
| VPR-014 | Policy publisher: `vpr publish` uploads the canonical document (IPFS or HTTPS) and prints the Safe transaction data | Fetched document hashes to the on-chain `contentHash` |
| VPR-015 | Resolver sync daemon: watches `PolicyPublished`, fetches and verifies the document, recompiles RPZ, reloads Unbound | Refuses documents whose hash mismatches; logs only version numbers; integration test with a local chain |
| VPR-016 | Metrics exporter for Unbound RPZ hits → `(school_id, day, category)` | No IPs or qnames leave the process (unit test asserts emitted fields); school_id derived from source network mapping |
| VPR-017 | Block page with appeal form that calls `fileAppeal` through a relayer | Appeal text limited to domain + reason; no personal data fields; rate-limited; block page and form available in Spanish and Portuguese, with strings in a translation file |
| VPR-018 | Black-box test kit for reviewers (`tools/reviewer/`) | Checks blocked categories, exceptions reachable, DNSSEC validation, external DoH/DoT/alternative DNS bypass; test traffic indistinguishable from ordinary clients (no fixed source, unannounced schedule); outputs a public summary, a full report and its hash |
| VPR-047 | Use Giga Maps school identifiers as `school_id` in the exporter mapping, attestations and datasets | Every attested school resolves to a Giga Maps record; the dashboard joins metrics with Giga Maps data by identifier |
| VPR-048 | **Done in 0.2.0.** Redesign appeal storage: the contract stores only a versioned, size-bounded commitment to an appeal document validated off-chain, never a caller-supplied free-text URI; reasoned resolutions and resubmission after rejection | Direct calls cannot place arbitrary text on-chain; tests cover oversize, wrong scheme and resubmission; INTERFACES I9 and DO_NO_HARM H6 updated |
| VPR-049 | **Format and schema done (pre-audit hardening); real manifests are published at deployment.** Deployment manifest per network (`deployments/<network>.json`), published by the partners: chain id, registry and anchor addresses, scope ids, expected governors and issuer roles; dashboard and tools pin it | A scope created under a canonical-looking name by another address is shown as untrusted; alert on governor, Safe owner or threshold changes |
| VPR-019 | Unbound hardening: block outbound DNS to public resolvers, DoH endpoint list | Bypass tests in VPR-018 fail as expected |

## M3 · Metrics, audit and registry on mainnet (weeks 9–16)

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-020 | Daily job: aggregate, publish CSV/JSON, `commitRoot` | Idempotent; a day can be recomputed by anyone with `vpr verify-root` |
| VPR-021 | Public dashboard (static site) reading registry, EAS and anchor | Shows policy in force + history with reasons, schools with valid attestations, daily metrics with verification button |
| VPR-022 | NIST SP 800-81r3 compliance matrix `docs/compliance/nist-800-81r3.md` | Each applicable recommendation mapped to config or control, with evidence |
| VPR-023 | UK Safer Internet Centre self-certification checklist | Completed and published in `docs/compliance/` |
| VPR-024 | Static analysis (MIESC, Slither) and external audit of the registry, anchor and resolver configuration, with fixes and a re-check | Public audit report; no open high-severity finding after re-check |
| VPR-025 | DPG application package | Every Gap and Credible-path row in `docs/DPG_EVIDENCE_MATRIX.md` closed or re-assessed; all 9 DPG Standard indicators evidenced with links; application submitted by the authorised representative |
| VPR-027 | **Done in 0.2.0.** Domain-separate Merkle leaves and internal nodes (RFC 9162-style `0x00`/`0x01` prefixes) in `MetricsAnchor.verifyLeaf`, `tools/vpr/merkle.py` and the JavaScript tests | An internal node presented as a leaf no longer verifies; shared test vector updated in all three implementations; ADR and new dataset format version per INTERFACES.md |
| VPR-026 | Impact report template | Uses only published aggregates |

## M4 · Zero-knowledge aggregation, reference implementation (weeks 5–16, testnet)

Statement to prove for each daily release: the published table is the k-suppressed aggregation of an event log committed by `logCommitment`, and every event's category belongs to the policy in force (content hash *h*). The event log stays private.

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-033 | ZK specification (`docs/specs/zk-aggregation.md`), produced in M1: statement, public and private inputs, hiding event-log commitment, proving-system evaluation (zkVM vs. dedicated circuit) | Reviewed in the M1 design review; chosen system justified with estimated proving cost |
| VPR-034 | Reference implementation of the statement in Python, used as the test oracle | Accepts valid (log, release) pairs and rejects altered counts, wrong suppression and out-of-policy categories |
| VPR-030 | Circuit or zkVM program for counting, k-suppression and category membership | Matches the oracle on randomised tests, including edge cases (empty day, all cells suppressed, k boundary) |
| VPR-036 | Benchmarks on commodity hardware | Proving time, memory and on-chain verification gas for 50 schools × 1 day; documented in the spec; per-school fallback decided before the freeze |
| VPR-035 | On-chain verifier and an anchoring function that accepts a daily root only with a valid proof | Tests for valid proof, altered root, wrong policy hash and replay; INTERFACES and ARCHITECTURE updated; frozen at end of week 12 |
| VPR-037 | Prover in the daily job; proofs published with each release; `vpr verify-proof` | Every alpha release from week 14 has a proof accepted by the verifier on OP Sepolia; mainnet verification follows the circuit audit in phase 2; an outside party verifies one with the CLI |

## Future work

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-031 | Verifiable differential privacy for overlapping releases (noise from committed public randomness or proven sampling) | Write-up with privacy budget, utility on synthetic data and verification cost |
| VPR-032 | TEE remote attestation (TDX, SEV-SNP or Nitro) for resolver and exporter, to bind the event log to a measured binary | Prototype binding a measured binary and the zone hash to an attestation; threat analysis of the TEE trust assumptions |
| VPR-038 | Canary events: reviewer test queries recorded as canaries and proven included in the committed log after release | Reviewer kit generates canaries without telling the operator the day; inclusion proof or explicit failure for every canary; detection probability against omission documented in the spec |

## Hygiene

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-040 | Add `slither`/MIESC and `ruff` to CI | CI fails on high-severity findings and lint errors |
| VPR-041 | Gas report for typical operations | Table in `docs/ARCHITECTURE.md` |
| VPR-042 | Fuzz/invariant tests for the registry (Foundry or Echidna) | Invariants from VPR-001 hold under fuzzing |
| VPR-070 | Integration test of `IssuerRoleResolver` against the real EAS contracts (`SchemaRegistry` + `EAS.attest`, as a devDependency or a fork test), and a deployment check that each schema's registered resolver has the matching `SchemaKind` | Test attests and is refused through EAS itself; deployment script fails on a mismatch |
| VPR-046 | End-to-end demo (`examples/e2e/run.sh`): policy, registry, RPZ, aggregation, anchored root and row verification on a local network | Runs from a clean checkout with one command; CI job green on every push |
| VPR-043 | REUSE compliance: SPDX headers on every file, `REUSE.toml` for files without headers | `reuse lint` passes in CI |
| VPR-044 | Docs site (MkDocs or similar) published from `docs/` | Site builds in CI and is linked from the README |
