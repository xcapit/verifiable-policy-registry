# Project governance

This page explains how the open-source project is run: who decides what goes into the code and the documents. It is different from the governance of each **filtering policy**, which belongs to the institutions that sign it (see [docs/GOVERNANCE.md](docs/GOVERNANCE.md)).

## Ownership

The Verifiable Policy Registry is developed and maintained by **Xcapit** (CryptoLab S.A.S., Córdoba, Argentina), which holds the copyright of the original code and documentation. Contributors keep the copyright of their contributions and license them under the project licences (see [NOTICE](NOTICE) and [CONTRIBUTING.md](CONTRIBUTING.md)). The licences are irrevocable: the project remains usable by anyone even if Xcapit stops maintaining it.

## Roles

| Role | Who | Responsibilities |
| --- | --- | --- |
| Contributor | Anyone who opens an issue or pull request | Follow the Code of Conduct and the contribution guide |
| Maintainer | Listed in [MAINTAINERS.md](MAINTAINERS.md) | Review and merge pull requests, triage issues, cut releases |
| Lead maintainer | Listed in [MAINTAINERS.md](MAINTAINERS.md) | Final call when maintainers disagree; security response; roadmap |
| Advisors | Partner institutions (for example the pilot's governance signers) | Review changes to the privacy model, issuer roles and filtering profiles; they have no merge rights |

New maintainers are proposed by an existing maintainer after sustained contributions and accepted by consensus of the current maintainers. Inactive maintainers (no activity for 12 months) move to emeritus.

## How decisions are made

- **Day-to-day changes** (bug fixes, tests, docs, backlog items): one maintainer approval.
- **Contracts, schemas and the privacy model**: two maintainer approvals, plus an [ADR](docs/adr) when behaviour or an interface changes.
- **Changes to the core principles** (no personal data, issuer separation, mandatory expiry, narrow scope, restricted lists by hash only): an ADR open for comments for at least 14 days, and advisor consultation. These principles protect children and the public; they are not changed for convenience.
- Maintainers seek consensus. When it cannot be reached, the lead maintainer decides and records the reasoning in the ADR or issue.

## Transparency

Decisions are recorded where anyone can read them: ADRs in [`docs/adr/`](docs/adr), discussion in issues and pull requests, releases in [CHANGELOG.md](CHANGELOG.md). Private channels are used only for security reports and Code of Conduct cases.

## Funding and independence

Funding sources for the project are listed in the README once confirmed. Funders do not get merge rights or a veto over the core principles.

## Changes to this document

Through a pull request with two maintainer approvals.
