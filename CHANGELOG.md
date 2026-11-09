# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). Interface changes are described in [docs/INTERFACES.md](docs/INTERFACES.md).

## [Unreleased]

### Added
- Interface specification for every component boundary (`docs/INTERFACES.md`) and JSON schemas for policy documents and datasets.
- Architecture decision records (`docs/adr/`).
- Digital Public Good readiness map (`docs/DPG.md`) and do-no-harm analysis (`docs/DO_NO_HARM.md`).
- Community files: code of conduct, security policy, project governance, maintainers, support, issue and pull request templates.
- Licence texts for CC0-1.0 and CC-BY-4.0 in `LICENSES/`, and a `NOTICE` file.

## [0.1.0] - 2026-11-09

### Added
- `VerifiablePolicyRegistry` contract: scopes, governors, versioned policies with reason and mandatory expiry, appeals.
- `MetricsAnchor` contract: write-once daily Merkle roots and on-chain leaf verification.
- `vpr` Python tools: policy validation and hashing, RPZ compilation, k-anonymous aggregation, Merkle proofs, CLI.
- EAS schema definitions, reference Unbound configuration, white paper, architecture, roadmap and backlog.
