# ADR-0005: Separate issuers: the operator never certifies itself

- Status: Accepted
- Date: 2026-11-09

## Context

The chain can prove which policy is in force, but not that a resolver applies it. That gap has to be covered by people who do not run the resolver.

## Decision

Three EAS schemas with distinct issuers: the operator attests deployments (`VPR.Deployment.v1`), the independent reviewer attests black-box tests (`VPR.IndependentTest.v1`) and an auditor attests conformance to a framework (`VPR.Conformance.v1`). A school counts as protected only with a valid reviewer attestation.

## Consequences

The pilot needs a real independent reviewer (a child-protection NGO or a university). Dashboards must check the attester address against the role registry of the scope.
