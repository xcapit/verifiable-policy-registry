# Backlog

Issue-ready tasks after the proof of concept. Each has acceptance criteria so it can be implemented spec-first. IDs are stable; reference them in commits (`VPR-012: ...`).

## M1 · Application and initial design (weeks 1–4)

See the week-by-week plan in [ROADMAP.md](ROADMAP.md#m1--application-and-initial-design--weeks-14--10). VPR-033 (ZK specification) is also delivered in this milestone.

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-001 | Write `docs/specs/registry.md`: formal spec of both contracts (state, events, errors, invariants) | Every external function documented with pre/post-conditions; invariants listed (versions append-only, expiry mandatory, appeal state machine) |
| VPR-002 | Write `docs/specs/eas.md`: schema fields, issuer roles, revocation rules, validity windows | Matches `schemas/eas-schemas.json`; defines who may issue/revoke each schema |
| VPR-003 | Threat model `docs/THREAT_MODEL.md` (STRIDE per component) | Covers registry, governor keys, resolver, exporter, aggregator, block page; each threat mapped to a mitigation or accepted risk |
| VPR-004 | DPIA template `docs/DPIA.md` aligned with UNICEF Policy on Personal Data Protection | Sections for data inventory, necessity, risks, mitigations; reviewed by Giga |
| VPR-005 | Finalise `docs/PRIVACY_STATEMENT.md` (RFC 8932 RPS) | Placeholders resolved; `vpr` command prints its keccak256 |
| VPR-006 | Filtering profiles: `policies/profiles/{primary,secondary,teachers}.yaml` mapped to ITU COP categories | Each validates with `vpr policy-hash`; mapping table in `docs/PROFILES.md` |
| VPR-007 | Validate policy documents against `schemas/policy.schema.json` in `vpr.policy.validate` (`valid_days`, `reason_code`, `profile`, `threat_feeds`, unknown keys) | Invalid example documents fail with a clear message; the shipped example passes; schema and code agree on every field |
| VPR-008 | `vpr restricted-hash <file>` command printing the restricted list commitment | Output equals `policy.restricted_list_hash()`; documented in `docs/INTERFACES.md` |
| VPR-009 | Restrict `MetricsAnchor.configure` so only the registry governor of a scope (or a factory) can configure it | A third party cannot claim a scope; tests cover the front-running case; INTERFACES updated |
| VPR-045 | Domain-separate Merkle leaves and internal nodes (for example RFC 9162-style `0x00`/`0x01` prefixes) in `MetricsAnchor.verifyLeaf`, `tools/vpr/merkle.py` and the JavaScript tests | An internal node presented as a leaf no longer verifies; shared test vector updated in all three implementations; ADR and new dataset format version per INTERFACES.md |

## M2 · Registry, resolver and attestations (weeks 5–10)

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-010 | Deployment scripts (Hardhat Ignition or scripts/) for OP Sepolia and OP Mainnet | One command deploys both contracts and creates a scope with a Safe as governor; addresses written to `deployments/<network>.json` |
| VPR-011 | Safe integration: script to propose `publishPolicy` as a Safe transaction | Proposal appears in the Safe UI; executed with 2 of 3 signatures on testnet |
| VPR-012 | EAS schema registration script | Registers the three schemas on OP Sepolia; UIDs stored in `deployments/` |
| VPR-013 | `vpr attest-deployment` and `vpr attest-test` CLI commands (EAS SDK or ethers) | Creates attestations on testnet; reviewer key and operator key are distinct; README documents usage |
| VPR-014 | Policy publisher: `vpr publish` uploads the canonical document (IPFS or HTTPS) and prints the Safe transaction data | Fetched document hashes to the on-chain `contentHash` |
| VPR-015 | Resolver sync daemon: watches `PolicyPublished`, fetches and verifies the document, recompiles RPZ, reloads Unbound | Refuses documents whose hash mismatches; logs only version numbers; integration test with a local chain |
| VPR-016 | Metrics exporter for Unbound RPZ hits → `(school_id, day, category)` | No IPs or qnames leave the process (unit test asserts emitted fields); school_id derived from source network mapping |
| VPR-017 | Block page with appeal form that calls `fileAppeal` through a relayer | Appeal text limited to domain + reason; no personal data fields; rate-limited |
| VPR-018 | Black-box test kit for reviewers (`tools/reviewer/`) | Checks blocked categories, exceptions reachable, DNSSEC validation, external DoH/DoT/alternative DNS bypass; test traffic indistinguishable from ordinary clients (no fixed source, unannounced schedule); outputs a public summary, a full report and its hash |
| VPR-019 | Unbound hardening: block outbound DNS to public resolvers, DoH endpoint list | Bypass tests in VPR-018 fail as expected |

## M3 · Metrics, dashboard and audit (weeks 8–16)

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-020 | Daily job: aggregate, publish CSV/JSON, `commitRoot` | Idempotent; a day can be recomputed by anyone with `vpr verify-root` |
| VPR-021 | Public dashboard (static site) reading registry, EAS and anchor | Shows policy in force + history with reasons, schools with valid attestations, daily metrics with verification button |
| VPR-022 | NIST SP 800-81r3 compliance matrix `docs/compliance/nist-800-81r3.md` | Each applicable recommendation mapped to config or control, with evidence |
| VPR-023 | UK Safer Internet Centre self-certification checklist | Completed and published in `docs/compliance/` |
| VPR-024 | Security analysis with MIESC + external audit preparation | Findings triaged; no open high-severity issues |
| VPR-025 | DPG application package | Every item in the *Still to do* list of `docs/DPG.md` closed; all 9 DPG Standard indicators evidenced with links; application submitted by the authorised representative |
| VPR-027 | Domain-separate Merkle leaves and internal nodes (RFC 9162-style tags) in Solidity, JS and Python, with a new shared test vector | `verifyLeaf` rejects an internal node presented as a leaf; dataset format version bumped; INTERFACES updated |
| VPR-026 | Impact report template | Uses only published aggregates |

## M4 · Zero-knowledge proofs of aggregation (weeks 5–16)

Statement to prove for each daily release: the published table is the k-suppressed aggregation of an event log committed by `logCommitment`, and every event's category belongs to the policy in force (content hash *h*). The event log stays private.

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-033 | ZK specification (`docs/specs/zk-aggregation.md`), produced in M1: statement, public and private inputs, event-log commitment, proving-system evaluation (zkVM vs. dedicated circuit) | Reviewed in the M1 design review; chosen system justified with estimated proving cost |
| VPR-034 | Reference implementation of the statement in Python, used as the test oracle | Accepts valid (log, release) pairs and rejects altered counts, wrong suppression and out-of-policy categories |
| VPR-030 | Circuit or zkVM program for counting, k-suppression and category membership | Matches the oracle on randomised tests, including edge cases (empty day, all cells suppressed, k boundary) |
| VPR-036 | Benchmarks on commodity hardware | Proving time, memory and on-chain verification gas for 50 schools × 1 day; documented in the spec; per-school fallback decided before the freeze |
| VPR-035 | On-chain verifier and an anchoring function that accepts a daily root only with a valid proof | Tests for valid proof, altered root, wrong policy hash and replay; INTERFACES and ARCHITECTURE updated; frozen at end of week 12 |
| VPR-037 | Prover in the daily job; proofs published with each release; `vpr verify-proof` | Every release in the last four weeks of the pilot has a proof accepted on-chain; an outside party verifies one with the CLI |

## Future work

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-031 | Verifiable differential privacy for overlapping releases (noise from committed public randomness or proven sampling) | Write-up with privacy budget, utility on synthetic data and verification cost |
| VPR-032 | TEE remote attestation (TDX, SEV-SNP or Nitro) for resolver and exporter, to bind the event log to a measured binary | Prototype binding a measured binary and the zone hash to an attestation; threat analysis of the TEE trust assumptions |

## Hygiene

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-040 | Add `slither`/MIESC and `ruff` to CI | CI fails on high-severity findings and lint errors |
| VPR-041 | Gas report for typical operations | Table in `docs/ARCHITECTURE.md` |
| VPR-042 | Fuzz/invariant tests for the registry (Foundry or Echidna) | Invariants from VPR-001 hold under fuzzing |
| VPR-043 | REUSE compliance: SPDX headers on every file, `REUSE.toml` for files without headers | `reuse lint` passes in CI |
| VPR-044 | Docs site (MkDocs or similar) published from `docs/` | Site builds in CI and is linked from the README |
