# ADR-0002: AGPL-3.0 for code, CC0 for schemas, CC BY 4.0 for docs

- Status: Superseded in part by [ADR-0011](0011-licence-split-and-dataset-licence.md) (contracts, verifier and datasets)
- Date: 2026-11-09

## Context

The project is meant to become a Digital Public Good, which requires an approved open licence. The main risk we want to avoid is a closed fork: an operator running a modified filter as a service without publishing the changes, which would defeat the purpose of a verifiable registry. At the same time, attestation schemas only work if anyone can adopt them without friction.

## Decision

- Code: GNU AGPL-3.0-only. Anyone who runs a modified version as a network service must offer its source.
- EAS schemas and JSON schemas: CC0-1.0, so other projects and the EAS community can reuse them freely.
- Documentation: CC BY 4.0.

## Consequences

Some companies avoid AGPL code. We accept that: the institutions we target (ministries, UN agencies, NGOs) can use AGPL without issue, and commercial operators can still run the software as long as they publish their changes.

## Alternatives considered

Apache-2.0 or MIT for everything: simpler, but allows closed hosted forks of the resolver tooling.
