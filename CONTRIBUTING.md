# Contributing

- Pick a task from [docs/BACKLOG.md](docs/BACKLOG.md) and reference its ID in commits (`VPR-015: resolver sync daemon`).
- Contracts: every new external function needs Hardhat tests and an entry in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Tools: `pytest` must pass; keep the Merkle scheme identical to the contracts (shared test vector).
- Never add personal data, real blocklists or restricted lists to the repository. Use `.example` domains.
- By contributing you agree that code is licensed under AGPL-3.0-only, schemas under CC0-1.0 and documentation under CC BY 4.0.

## Security

Report vulnerabilities privately to the maintainers at Xcapit before opening a public issue.
