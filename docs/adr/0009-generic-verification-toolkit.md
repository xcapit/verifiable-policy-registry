# ADR-0009: A use-case-independent verification toolkit

- Status: Accepted
- Date: 2026-11-09

## Context

The commitment and verification code was written for school filtering, with `school_id` in its names. Funders and other builders need to see that the same machinery serves other public-interest metrics, and integrators need a stable surface that does not import filtering logic.

## Decision

- `vpr.toolkit` is the stable Python API (version 1): document hashing, aggregation with suppression, release roots, row proofs and verification. It contains no school- or filtering-specific code.
- The unit column of a release may be named `school_id` or `unit_id`. The leaf encoding and the root are identical, so the same contract function (`MetricsAnchor.verifyRow`) verifies both.
- The CLI gains `prove-row`, `verify-row`, `evaluate` and `--json` output, with exit codes 0 (ok), 1 (mismatch) and 2 (invalid input).
- A second synthetic use case (public-service interruptions) is maintained in `examples/public-service/` and exercised by the demonstrator and the tests.

## Consequences

The school use case keeps working unchanged. The toolkit API is versioned separately from the dataset format (see the [integration guide](../toolkit/INTEGRATION_GUIDE.md)). Algorithms are not duplicated: the CLI, the demo and the examples all call the same functions, and Solidity and Python share test vectors.

## Alternatives considered

A separate package for the toolkit: cleaner boundaries, but two release processes for a small codebase. Deferred until there is an external user who needs it.
