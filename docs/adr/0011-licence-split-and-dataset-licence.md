# ADR-0011: Apache-2.0 for contracts and verifier, CC0 for published datasets

- Status: Accepted
- Date: 2026-11-10
- Supersedes in part: [ADR-0002](0002-licensing.md)

## Context

ADR-0002 placed all code under AGPL-3.0-only to prevent closed hosted forks of the filtering service. Two consequences became visible while preparing the project for reuse by other builders and for DPG registration.

1. The components meant for reuse outside this deployment are the contracts (`VerifiablePolicyRegistry`, `MetricsAnchor`, `IssuerRoleResolver`) and the planned zero-knowledge verifier. Projects that build on Ethereum commonly avoid AGPL dependencies in their own contracts, so AGPL there works against adoption. The risk ADR-0002 addresses, a modified filter run as a closed service, lies in the resolver and operations tooling, not in contracts whose deployed bytecode is public anyway.
2. The licence of published datasets was undeclared (VPR-059). The DPG Standard asks for an open licence on data, and anyone must be able to recompute and republish a release to check it.

## Decision

- **Contracts and verifier: Apache-2.0.** This covers `contracts/` and, once it exists, `zk/` (circuit or zkVM program, on-chain verifier and verification library). Apache-2.0 includes an explicit patent grant, which matters for cryptographic code.
- **All other code: AGPL-3.0-only, unchanged.** This covers `tools/`, `deploy/`, `examples/` and the operations components to come (sync daemon, exporter, relayer, dashboard).
- **Published datasets: CC0-1.0.** Daily aggregate releases contain no personal data, only counts at or above the suppression threshold. CC0 removes every condition on reuse, including attribution, so researchers, journalists and auditors can recompute, mirror and combine releases. It matches the licence of the schemas that define the format, and the DPG Standard accepts it for data. ODC-PDDL was the alternative; it has the same effect but is less widely recognised outside the open-data community and has no fallback licence where a public-domain dedication is not legally possible.
- Schemas stay CC0-1.0 and documentation stays CC BY 4.0.

All existing contract code was written by Xcapit staff, so the copyright holder can relicense it.

## Consequences

- Other projects can embed the contracts and the verifier in their own code under permissive terms.
- A closed fork of the contracts is possible, but it does not undermine accountability: what a deployment commits to is on a public chain, and the off-chain operations tooling remains AGPL.
- Operators who publish releases dedicate them to the public domain. The scope charter of each deployment records this, because the dataset publisher, not Xcapit, holds the rights in the published figures.
- Contributions follow the licence of the path they touch ([CONTRIBUTING](../../CONTRIBUTING.md#licensing-of-contributions)).
