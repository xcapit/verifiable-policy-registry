# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). Interface changes are described in [docs/INTERFACES.md](docs/INTERFACES.md).

## [Unreleased]

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
