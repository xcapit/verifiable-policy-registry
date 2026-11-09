# Backlog

Issue-ready tasks after the proof of concept. Each has acceptance criteria so it can be implemented spec-first. IDs are stable; reference them in commits (`VPR-012: ...`).

## M1 · Specification

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-001 | Write `docs/specs/registry.md`: formal spec of both contracts (state, events, errors, invariants) | Every external function documented with pre/post-conditions; invariants listed (versions append-only, expiry mandatory, appeal state machine) |
| VPR-002 | Write `docs/specs/eas.md`: schema fields, issuer roles, revocation rules, validity windows | Matches `schemas/eas-schemas.json`; defines who may issue/revoke each schema |
| VPR-003 | Threat model `docs/THREAT_MODEL.md` (STRIDE per component) | Covers registry, governor keys, resolver, exporter, aggregator, block page; each threat mapped to a mitigation or accepted risk |
| VPR-004 | DPIA template `docs/DPIA.md` aligned with UNICEF Policy on Personal Data Protection | Sections for data inventory, necessity, risks, mitigations; reviewed by Giga |
| VPR-005 | Finalise `docs/PRIVACY_STATEMENT.md` (RFC 8932 RPS) | Placeholders resolved; `vpr` command prints its keccak256 |
| VPR-006 | Filtering profiles: `policies/profiles/{primary,secondary,teachers}.yaml` mapped to ITU COP categories | Each validates with `vpr policy-hash`; mapping table in `docs/PROFILES.md` |

## M2 · Registry and attestations

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
| VPR-018 | Black-box test kit for reviewers (`tools/reviewer/`) | Checks blocked categories, exceptions reachable, DNSSEC validation, external DoH/DoT/alternative DNS bypass; outputs a report and its hash |
| VPR-019 | Unbound hardening: block outbound DNS to public resolvers, DoH endpoint list | Bypass tests in VPR-018 fail as expected |

## M3 · Metrics and audit

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-020 | Daily job: aggregate, publish CSV/JSON, `commitRoot` | Idempotent; a day can be recomputed by anyone with `vpr verify-root` |
| VPR-021 | Public dashboard (static site) reading registry, EAS and anchor | Shows policy in force + history with reasons, schools with valid attestations, daily metrics with verification button |
| VPR-022 | NIST SP 800-81r3 compliance matrix `docs/compliance/nist-800-81r3.md` | Each applicable recommendation mapped to config or control, with evidence |
| VPR-023 | UK Safer Internet Centre self-certification checklist | Completed and published in `docs/compliance/` |
| VPR-024 | Security analysis with MIESC + external audit preparation | Findings triaged; no open high-severity issues |
| VPR-025 | DPG application package | All 9 DPG Standard indicators evidenced with links |
| VPR-026 | Impact report template | Uses only published aggregates |

## M4 · Research

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-030 | ZK prototype: prove the published aggregate equals the sum of committed per-block events under policy vN | Prototype circuit + benchmark + write-up |

## Hygiene

| ID | Task | Acceptance criteria |
| --- | --- | --- |
| VPR-040 | Add `slither`/MIESC and `ruff` to CI | CI fails on high-severity findings and lint errors |
| VPR-041 | Gas report for typical operations | Table in `docs/ARCHITECTURE.md` |
| VPR-042 | Fuzz/invariant tests for the registry (Foundry or Echidna) | Invariants from VPR-001 hold under fuzzing |
