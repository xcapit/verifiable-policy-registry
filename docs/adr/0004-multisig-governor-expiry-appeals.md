# ADR-0004: Multisig governor per scope, mandatory expiry, on-chain appeals

- Status: Accepted
- Date: 2026-11-09

## Context

A filter that one party can change silently can be turned into a censorship tool. Blocks also tend to become permanent because nobody reviews them.

## Decision

- Each scope has one governor address, expected to be a Safe multisig. Pilot: 2-of-3 with UNICEF Giga, the Ministry of Education and an independent reviewer.
- Every policy version has a mandatory validity bounded by the scope `maxValidity` (pilot: 90 days). An expired version is reported as not in force.
- Anyone can file an appeal on-chain. The governor accepts it by publishing a version that resolves it, or rejects it; both outcomes are public.

## Consequences

Renewal becomes an operational duty. The fallback when a policy expires is defined in the scope charter (recommended: protective categories only).

## Alternatives considered

Role-based access inside the contract: duplicates what Safe already does, with more code to audit.
