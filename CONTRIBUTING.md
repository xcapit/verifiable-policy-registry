# Contributing to the Verifiable Policy Registry

Thanks for wanting to help. This project protects children on school networks and, at the same time, has to stay accountable to the public. Both goals shape how we work, so please read this page before opening a pull request.

## Ground rules

1. **No personal data, ever.** Do not add IP addresses, device identifiers, queried domain names from real traffic, or anything that could identify a child or a teacher. This applies to code, tests, fixtures, issues and logs pasted in discussions.
2. **No real blocklists or restricted lists.** Lists such as the IWF URL List cannot be published. Examples and tests use `.example` domains only (see [`examples/`](examples)).
3. **Narrow scope.** The project targets bounded networks with an accountable governor (schools first). Features aimed at ISP-wide or national blocking will not be accepted. See [ADR-0006](docs/adr/0006-scope-school-networks-only.md).
4. **The operator never certifies itself.** Changes that blur issuer roles (operator, independent reviewer, auditor) need an ADR first.
5. **English** for code, comments, commit messages and repository documents. Discussion in issues can be in English or Spanish.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Where to start

- The [backlog](docs/BACKLOG.md) lists tasks with stable IDs (`VPR-0xx`) and acceptance criteria. Issues labelled `good first issue` are a good entry point.
- Comment on the issue before you start so we avoid duplicate work. If no issue exists, open one using the templates.
- For larger changes (new contract function, new attestation schema, a change in the privacy model), write a short ADR in [`docs/adr/`](docs/adr) and discuss it in the issue before writing code.

## Development setup

Requirements: Node.js 20+, Python 3.10+, git.

```bash
git clone https://github.com/xcapit/verifiable-policy-registry.git
cd verifiable-policy-registry

# Contracts
cd contracts
npm ci
npx hardhat test            # OFFLINE_SOLC=1 npx hardhat test if the native solc cannot be downloaded

# Off-chain tools
cd ../tools
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
pytest
```

Smoke test of the CLI from the repository root:

```bash
vpr policy-hash policies/example-primary.yaml
vpr aggregate examples/events.csv --k 10 --out-csv dataset.csv
```

## Making a change

1. Fork the repository and create a branch from `main`: `feat/VPR-015-sync-daemon`, `fix/merkle-odd-leaf`, `docs/interfaces-appeal`.
2. Keep pull requests small and focused on one backlog item.
3. Add or update tests. CI must be green.
4. Update the docs that your change touches:
   - a new or changed external contract function → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/INTERFACES.md`](docs/INTERFACES.md);
   - a change to a data format (policy document, dataset, events, attestation) → [`docs/INTERFACES.md`](docs/INTERFACES.md) and the JSON schemas in [`schemas/`](schemas);
   - anything user-visible → [`CHANGELOG.md`](CHANGELOG.md) under *Unreleased*.
5. Open the pull request and fill in the template.

### Rules for specific areas

- **Contracts.** Keep them minimal. Every new external function needs Hardhat tests (happy path, access control, reverts). No upgradeability proxies without an ADR.
- **Merkle scheme.** Solidity, JavaScript tests and `tools/vpr/merkle.py` must stay identical and share the same test vector. If you touch one, run both test suites.
- **Hashing.** The canonical JSON rule for policy documents is part of the public interface. Changing it changes every `contentHash`, so it needs an ADR and a new format version.
- **Metrics.** Code that handles resolver events must not accept fields other than `(school_id, day, category)`.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/) and reference the backlog ID when there is one:

```
feat(registry): add scope charter URI (VPR-001)
fix(tools): reject empty reason in exceptions
docs(interfaces): document appeal document format
```

Types we use: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `build`.

## Developer Certificate of Origin

Every commit must be signed off, certifying that you wrote the change or have the right to submit it under the project licences ([DCO 1.1](https://developercertificate.org/)):

```bash
git commit -s -m "fix(tools): reject empty reason in exceptions"
```

This adds a `Signed-off-by: Your Name <you@example.org>` line. We do not require a CLA.

## Licensing of contributions

By contributing you agree that your contribution is licensed under the licence of the part of the repository it touches:

| Path | Licence |
| --- | --- |
| Code (`contracts/`, `tools/`, `deploy/`, `.github/`) | [AGPL-3.0-only](LICENSE) |
| Schemas (`schemas/`) | [CC0-1.0](LICENSES/CC0-1.0.txt) |
| Documentation (`docs/`, Markdown files at the root) | [CC BY 4.0](LICENSES/CC-BY-4.0.txt) |

New source files start with an SPDX header, for example `// SPDX-License-Identifier: AGPL-3.0-only` or `# SPDX-License-Identifier: AGPL-3.0-only`.

## Review

A maintainer listed in [MAINTAINERS.md](MAINTAINERS.md) reviews every pull request. Changes to `contracts/`, `schemas/` or the privacy model need two approvals. We aim to give a first answer within five working days.

## Security issues

Do not open public issues for vulnerabilities. Follow [SECURITY.md](SECURITY.md).
