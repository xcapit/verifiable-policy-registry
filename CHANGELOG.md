# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). Interface changes are described in [docs/INTERFACES.md](docs/INTERFACES.md).

## [Unreleased]

### Added
- Bounded symbolic checks with Halmos 0.3.3 (`contracts/test-foundry/symbolic/`, `scripts/symbolic_check.py`, CI job `symbolic`).
  - The acceptance rule of every state-changing function of the registry and the anchor, for all inputs within stated bounds: success exactly when INTERFACES I2 and I7 accept the call, and the stored result on success.
  - Frame conditions under an arbitrary call: past versions, resolved appeals and written days are unchanged, and the governor holds no role.
  - The leaf encoding, as a secondary check.
  - Canaries that must fail, and 22 of the targeted mutants caught.
  - Claim C57.
- One-year workload benchmark for one scope (`contracts/scripts/bench-workload.js`, `docs/benchmarks/workload-gas.json`).
  - Execution gas per operation (min, median, max) with realistic hashes, URIs and transaction encoding; CI checks it exactly.
  - L1 data fee and L2 base fee from OP Mainnet's `GasPriceOracle` (`scripts/bench-l1fee.js`, read-only), calibrated against receipts and taken as the median of seven daily snapshots.
  - Finding: attestations per school and per version are 93 % of the execution gas, and the L1 data fee is most of each transaction's cost.
  - BENCHMARKS §2.1, contract assurance §8, cost model and claim C48 updated.

### Changed
- White paper v0.7.
  - Related work on transparency logs (tamper-evident history trees, gossip, witness cosigning, Sigsum, the Go checksum database), and the case for a ledger rather than a witnessed log.
  - The rollup trust model: unsafe, safe and finalized blocks; ledger safety and liveness defined; L2 upgrade keys and the Security Council; P-256 through RIP-7212.
  - P1 to P7 restated with adversary, assumptions and the mechanism or invariant that enforces each.
  - A section on who monitors the record.
  - Precise statements of the canonical form relative to RFC 8785 and of the Merkle tree relative to RFC 9162.
  - Corrections: the restricted-list commitment is not hiding (with Apple's committed database as prior art); appellant unlinkability needs the relayer; canaries must be indistinguishable to be effective.
  - Two stated limits of the governor design: institution-level concentration of roles, and no notice period before a version takes effect.
  - New adversary A11 (rollup governance).
  - New Figure 4: the states of a transaction on an OP Stack chain (unsafe, safe, finalized), what can still revert each, and the verifier's reading rule; later figures are renumbered.
  - Figure 11 (metrics pipeline): the leaf formula now shows the length prefixes of format 2, as in INTERFACES I6.
- INTERFACES, cryptographic evidence and threat model aligned with the white paper: canonical form and row order specified exactly; RFC 9162 scope stated; hash choice for the event log tied to the proving-system decision; T27 and T47 updated; T49 (L2 governance) added; claims C55 (finality and chain governance) and C56 (JCS equivalence, not yet tested) added. Figures 2, 3 and 15 updated.
- Documentation: the v0.3 planning reports (baseline and gap analysis, implementation report) are removed; they described how the release was prepared, not the system, and remain in the v0.3.0 to v0.5.0 tags. The reviewer guide (`docs/review/REVIEWER_GUIDE.md`) covers the current toolchain and scope.
- Stale statements corrected: anchor corrections in the cryptographic evidence and threat model (T12), the architecture sequence and on-chain data table, the opcode target in the public-goods case, ADR-0003's L1 cost argument, interface and version headers. ADR-0007 is renamed to match its corrected wording (small-cell suppression, not k-anonymity).
- The 15 mutants that did not come from the suites' authors are attributed to a separate internal review; no external review has taken place (claim C45).

## [0.5.0] - 2026-11-10

Contract assurance for external review: static analysis, specification-oracle invariants, mutation testing, coverage and gas gates in CI, and an integration test through the real EAS contracts. Contract logic is unchanged since v0.4.0. Research prototype: contracts not audited, schemas not registered on a public network, ZK proof of aggregation designed but not implemented, no public deployment. **Breaking change** to the deployment manifest (`finality` replaces `confirmations`).

### Added
- Contract assurance (`docs/security/CONTRACT_ASSURANCE.md`): Slither in CI failing on any finding; Foundry invariant suites for the registry and the anchor, with every call checked against an oracle written from the specification, and property fuzzing (shared vector, Merkle proofs, leaf encoding, scope ids, resolver roles and ABI head); a targeted mutation check (26 mutants, 15 from a separate internal review, run in a temporary copy) and a slither-mutate score over the whole test stack; coverage as a CI gate (100 % lines, 98 % branches minimum) and per-function gas reports; OP Stack time and ordering semantics, including the ±30-minute accuracy of L2 time (VPR-040 Slither part, VPR-041, VPR-042).
- Complete NatSpec on the three contracts (logic unchanged).
- Integration test of `IssuerRoleResolver` through the real EAS contracts (EAS and SchemaRegistry v1.4.0, deployed from the artifacts of the pinned npm package `@ethereum-attestation-service/eas-contracts` 1.9.0): issuance only by the role holder, refusal across scopes and after a role is withdrawn, revocation by the attester, batches, malformed data and value (VPR-070).
- `scripts/check-eas.js`: verifies a deployment manifest's EAS schema bindings (UID, schema string, resolver kind, registry and EAS wiring).

### Changed
- Contracts are compiled with `evmVersion: cancun`, pinned identically in Hardhat and Foundry.
- Contract sources are ASCII-only (checked in CI); comments only, logic unchanged.
- **Breaking (manifest).** `confirmations` is replaced by `finality` (`finalized`, `safe` or, for a local demonstrator, `latest`): on OP Stack a block count is not a finality policy.
- `scripts/check-eas.js` reports the deployed EAS and SchemaRegistry versions (OP Stack predeploys are upgradeable proxies).
- Deployment manifest: optional `contracts.eas` and `contracts.easSchemaRegistry`; `maxLagDays` follows the anchor semantics (1 to 2³²−1).

## [0.4.0] - 2026-11-09

Pre-audit hardening of the contracts, with a further internal review, and white paper v0.6. Research prototype: contracts not audited, schemas not registered on a public network, ZK proof of aggregation designed but not implemented, no public deployment. Pre-audit hardening (closes VPR-060, VPR-065 to VPR-069; the resolver part of VPR-012; the format of VPR-049). **Breaking changes** to the contracts and tools.

### Added
- `IssuerRoleResolver`: EAS schema resolver that accepts an attestation only if the attester holds the schema's role in the scope at issuance time.
- Deployment manifest format `vpr-manifest/1` (schema and synthetic example), validated in CI.
- Tools: `list-hash`, `zone-hash`, `check-onchain` (document versus on-chain values), `appeal-hash` (appeal format 3 with a random nonce), `policy-hash --governor`.
- `feed_hashes` in policy documents: compilation refuses a feed whose contents differ from the declared hash.

### Changed
- **Breaking.** Scope ids are `keccak256(abi.encode(governor, name))`, derived on-chain; `createScope(name, maxValidity)`.
- **Breaking.** Governor handover is two-step (`proposeGovernor`, `acceptGovernor`); `setGovernor` is removed. `maxValidity` is capped at 365 days; reason codes are validated (code 3 if and only if an appeal is resolved); policy and dataset URIs are capped at 256 bytes; the governor cannot hold an issuer role.
- **Breaking.** `MetricsAnchor.setPublisher(scopeId, publisher, maxLagDays)`: publishers can be revoked; future days are refused and back-filling can be limited; `markEmpty` declares days with nothing publishable; `correctRoot` lets the governor correct a root with a reason hash and a revision count.
- Appeal documents move to format 3 (`nonce`), so they cannot be guessed and pre-filed.

White paper version 0.6: wording aligned with the hardened contracts (scope identifiers, issuer-role enforcement, anchoring window and governor corrections, appeal format 3), stale figure labels corrected (leaf encoding, `verifyRow`), eleven new figures added and the roadmap figure reused, so that every main section has one (19 in total).

Changes after a further internal review of this hardening:
- **Breaking.** `MetricsAnchor` anchors only days that have ended (`DayNotClosed` replaces `DayInFuture`). The lag is explicit: `maxLagDays` is at least 1 for an appointed publisher, `NO_LAG_LIMIT` disables the bound, and 0 is used only to revoke (`InvalidLag`). A key-compromised publisher can no longer back-fill history by default.
- **Breaking.** `correctRoot` can turn a root back into an empty day (`newRoot` 0) and refuses no-op corrections (`NoChange`); `RootCorrected` now carries the new `datasetUri`.
- **Breaking.** `IssuerRoleResolver(eas, registry, SchemaKind)`: the schema kind fixes the role and the ABI layout; the head of `data` and the first string offset are checked; `version()` added; `NotPayable` and `LengthMismatch` errors.
- The governor cannot hold an issuer role across a handover: an issuer cannot be proposed, the pending governor cannot be given a role, and `acceptGovernor` re-checks. Scope names are capped at 128 bytes; `getVersion` reverts `UnknownVersion`; pragmas pinned to `=0.8.24`.


## [0.3.0] - 2026-11-09

Evidence-driven readiness for external review, with a second security and privacy review. Research prototype: contracts not audited, ZK proof of aggregation designed but not implemented, no public deployment.

### Added
- Baseline and gap analysis, claims-and-evidence ledger, reviewer guide mapped to the 14 review questions.
- Cryptographic evidence pack: normative encodings, test vectors, designed ZK relation with every bound input, hiding event-log commitment, canary limits, risk register, proving-system decision record (ZK remains Designed).
- Threat model (37 threats with owners and verification methods) and privacy and re-identification analysis with data inventory and release-policy framework.
- Generic verification toolkit (`vpr.toolkit`, API v1), `unit_id` releases, second synthetic use case (public-service interruptions), CLI `evaluate`, `prove-row`, `verify-row`, `--json` and exit codes 0/1/2 (ADR-0009).
- Demonstrator: zone evaluation of allowed and blocked domains, two use cases on one verifier, read-back of roots, rejection of tampered rows, wrong roots and modified documents, appeal rejection and resubmission, expiry, explicit ZK boundary, machine-readable evidence manifest; CI uploads it with a benchmark.
- Benchmarks with environments; Giga pilot-readiness package; ESP evidence package; DPG nine-indicator evidence matrix (self-assessment, checked against the DPGA's published versions).
- ADR-0010 (category and unit sets on-chain for the ZK relation, proposed); policy-governance safeguards (scope charter, never-blocked categories, emergency changes, external recourse, monitoring of signer changes).

### Fixed
- A release-validation error message could echo suppressed cells; it no longer contains values.
- Malformed YAML policies crashed the CLI with a traceback; they now fail with exit code 2.
- The tools package could not be installed in editable mode once a second top-level directory existed.
- An exception in a policy could cancel a restricted-list entry; compilation now refuses it without naming the entry. Empty feeds and invalid block pages are refused; zones are deterministic and written 0600.
- Event input now enforces the privacy boundary on content: units and categories must be identifiers, so domains and IP addresses cannot reach a release; rows, dates and counts are parsed strictly.
- Restricted-list entries no longer appear in error messages; duplicate YAML keys are rejected.
- Zone evaluation fails closed on records it does not understand and handles TTL, class, case, NODATA and drop.
- CLI: unexpected errors exit 2 without a traceback; `verify-row` without `--root` reports `anchored: false`; `verify-root --k` checks the threshold.
- The reference Unbound fragment did not load; it now passes `unbound-checkconf` with deployment files substituted.
- The demonstrator's wrong-root check could never fail; negative checks now assert exact custom errors.

### Changed
- ZK specification (Designed): the event count *m* stays private, *k* is read from the registry, the scope is bound in each event leaf.
- Threat model T38–T48 and backlog VPR-061 to VPR-069 from the second review; contract-level hardening is scheduled before the M3 audit freeze.
- README status box separating implemented, demonstrated, designed, audit and deployment status; tagline no longer says "privacy-preserving" without qualification. White paper v0.5 defers to the evidence documents.

## [0.2.0] - 2026-11-09

Hardened contracts and data formats, an end-to-end demo, the team, and a two-phase pilot plan, following external review. Contracts are still not audited. This release breaks compatibility with 0.1.0: the `MetricsAnchor` constructor and publisher model, `verifyRow` in place of `verifyLeaf`, dataset format 2 and appeal format 2.

### Added
- Issuer roles on-chain: `setIssuer` and `issuerRole`, one role per address per scope.
- `vpr restricted-hash` command and runtime validation of the full policy schema (VPR-007, VPR-008).
- End-to-end demo (`examples/e2e/run.sh`) and CI job: policy, registry, RPZ, aggregation, anchored root, verification of a published and a tampered row (VPR-046).
- CI check of internal links and heading anchors.
- README sections on running the demo and on components other builders can reuse.
- `docs/SUSTAINABILITY.md`: cost model per school, operating options after the pilot, handover package, behaviour if funding stops.
- Deployment conditions (satellite links, provider configuration, unreachable resolver) and integration with Giga Maps identifiers and Giga Meter, in the architecture and the white paper; Giga Maps identifiers as `school_id` (VPR-047).

### Changed
- Roadmap re-scoped into two phases. Phase 1 (four months): design and sign-off, testnet reference implementation with an alpha in 2–5 schools, audited registry on mainnet, and a ZK aggregation reference implementation on testnet, with gates A–C. Phase 2 (gated): 20–50 school cohort, circuit audit and mainnet verifier, impact over a school term.
- **Breaking (contracts).** `MetricsAnchor` takes the registry address; its publisher is appointed by the scope's governor (`setPublisher`), replacing first-caller `configure` (VPR-009). `verifyLeaf` is replaced by `verifyRow`, which computes the leaf from the row and the anchored day.
- **Breaking (dataset format 2).** Domain-separated leaves (0x00) and nodes (0x01), length-prefixed fields and the on-chain day in each leaf (VPR-027); releases cover one day with unique cells; the number of suppressed cells is no longer published; `vpr aggregate` takes `--day`.
- **Breaking (appeals, format 2).** `fileAppeal` stores only the hash of a validated appeal document; `rejectAppeal` requires the hash of a reasoned decision; a rejected document can be resubmitted in a new round (VPR-048).
- `createScope` can only be called by the governor it names; scope discovery relies on a deployment manifest (VPR-049).
- `vpr compile-rpz` fails closed when a category has no feed or when the restricted list does not match the declared hash.
- Team listed in MAINTAINERS.md and the README, with areas of responsibility.
- Privacy wording corrected: the resolver processes client addresses and queried names transiently; nothing identifying is retained, exported or published.
- DPG self-assessment re-checked against DPG Standard v1.1.6, with evidence-based status words; indicators 7 and 9 marked as gaps.
- Appeal storage redesign tracked as VPR-048; white paper reference to VPR-027 fixed.
- White paper v0.4: zero-knowledge proofs of aggregation described as planned for M4; the event-log commitment must be hiding; canary events as a partial check on log completeness.
- Roadmap: M1 renamed *Design and sign-off*, without the funding application; M4 acceptance window aligned with prover integration (from week 14); fallback acceptance if the circuit audit slips.
- Backlog: canary events (VPR-038); Spanish and Portuguese block page and appeal form (VPR-017).
- ADR-0007 retitled to describe small-cell suppression.

## [0.1.0] - 2026-11-09

First public release: a proof of concept and the documentation needed for external review. The contracts are not audited and not deployed on any production network.

### Contracts
- `VerifiablePolicyRegistry`: scopes, governors, versioned policies with reason and mandatory expiry, appeals.
- `MetricsAnchor`: write-once daily Merkle roots and on-chain leaf verification.

### Tools
- `vpr` Python package and CLI: policy validation and canonical hashing, RPZ compilation, aggregation with small-cell suppression, Merkle proofs.

### Schemas
- EAS attestation schemas with separate issuer roles; JSON Schemas for policy documents and datasets (CC0).

### Documentation
- White paper v0.3: system model with properties P1–P7, adversary model, related work, privacy analysis of the metrics, zero-knowledge proof of aggregation, seven figures.
- Architecture, interface specification for every component boundary, and architecture decision records.
- Four-month pilot roadmap, with zero-knowledge proofs of aggregation as a milestone, and a backlog with acceptance criteria.
- Policy governance, draft RFC 8932 privacy statement, do-no-harm analysis and DPG readiness map.
- Reference Unbound configuration.

### Project
- Code of conduct, security policy, project governance, maintainers, support, contribution guide with DCO, issue and pull request templates.
- Licence texts (AGPL-3.0-only, CC0-1.0, CC-BY-4.0), NOTICE, CITATION.cff and publiccode.yml.

[Unreleased]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/xcapit/verifiable-policy-registry/releases/tag/v0.1.0
