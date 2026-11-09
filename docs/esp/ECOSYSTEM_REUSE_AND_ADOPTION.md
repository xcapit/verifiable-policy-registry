# Ecosystem reuse and adoption

*CC BY 4.0 · Part of the ESP evidence package ([index](APPLICATION_EVIDENCE_INDEX.md)).*

## 1. Who could build on this

The components solve a recurring pattern: *an institution enforces a rule off-chain, and others need to verify how the rule was governed and what aggregate effect it had, without learning about individuals.* Possible adopters, none of whom has committed to anything:

| Builder or programme | Component they would reuse | Example |
| --- | --- | --- |
| Public or community Wi-Fi operators, libraries | Registry, schemas, RPZ tooling | Accountable content policy for a municipal network |
| Public-service and utility monitors | `MetricsAnchor`, aggregation and verification toolkit | Daily outage counts per district, committed and independently recomputable ([`examples/public-service/`](../../examples/public-service)) |
| Aid and social-protection programmes | Registry pattern, appeals by document hash, issuer separation | Eligibility rules that expire and can be contested |
| Attestation ecosystems | CC0 EAS schemas and the issuer-separation guidance | Any scheme in which an operator must not certify itself |
| Researchers in privacy-preserving statistics | ZK relation specification and test vectors | Verifiable suppressed aggregation as a benchmark problem |

## 2. What makes reuse practical

- **No school logic in the core.** The toolkit verifies datasets keyed by a generic unit identifier. The school example and the public-service example go through the same verifier ([integration guide](../toolkit/INTEGRATION_GUIDE.md)).
- **Stable, specified formats.** Policy format 1, dataset format 2 and appeal format 2 are specified in [INTERFACES](../INTERFACES.md) with shared test vectors across Solidity and Python.
- **Permissionless licences.** CC0 for schemas, CC BY 4.0 for documentation, AGPL-3.0-only for code. The AGPL requires that hosted modified versions publish their source, which protects the accountability purpose ([ADR-0002](../adr/0002-licensing.md)).
- **Runs without credentials.** The demonstrator and tests need no keys, RPC tokens or paid services ([README](../../README.md)).

## 3. How adoption would be measured

Metrics are counted from public sources only, and each has a defined method:

| Metric | Method | Baseline at v0.3 |
| --- | --- | --- |
| Independent deployments of the registry or anchor | Contracts with matching bytecode or an announced manifest, deployed by an address not controlled by the maintainers | 0 |
| Schema reuse | EAS attestations under the VPR schema UIDs issued by attesters outside the project | 0 (schemas not yet registered) |
| Independent verification runs | Published reports by parties outside the team that recomputed a root or verified a proof | 0 |
| Third-party integrations | Public repositories importing the toolkit or forking the contracts | To be measured from GitHub dependency and fork data |
| External contributions | Issues and merged pull requests from non-maintainers | To be measured from the repository |

Targets for these metrics are **TBD — maintainer input required**. They should be set conservatively, since the first phase produces infrastructure rather than a user base.

## 4. Stewardship

Project governance, maintainer roles and decision rules are in [GOVERNANCE.md](../../GOVERNANCE.md) and [MAINTAINERS.md](../../MAINTAINERS.md). Changes to formats require an ADR and a format-version bump, so that external integrators are not broken silently ([CONTRIBUTING](../../CONTRIBUTING.md)).
