# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). Interface changes are described in [docs/INTERFACES.md](docs/INTERFACES.md).

## [Unreleased]

### Added
- End-to-end demo (`examples/e2e/run.sh`) and CI job: policy, registry, RPZ, aggregation, anchored root, verification of a published and a tampered row (VPR-046).
- CI check of internal links and heading anchors.
- README sections on running the demo and on components other builders can reuse.
- `docs/SUSTAINABILITY.md`: cost model per school, operating options after the pilot, handover package, behaviour if funding stops.
- Deployment conditions (satellite links, provider configuration, unreachable resolver) and integration with Giga Maps identifiers and Giga Meter, in the architecture and the white paper; Giga Maps identifiers as `school_id` (VPR-047).

### Changed
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

[Unreleased]: https://github.com/xcapit/verifiable-policy-registry/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/xcapit/verifiable-policy-registry/releases/tag/v0.1.0
