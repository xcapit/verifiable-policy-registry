# ADR-0008: Restricted lists by hash commitment only

- Status: Accepted
- Date: 2026-11-09

## Context

Some lists, such as the IWF list of child sexual abuse material, cannot legally be published, and publishing them would cause harm.

## Decision

Restricted lists are referenced only by `restrictedListHash` on-chain and in the policy document. Their entries are merged by the operator at compile time and are never labelled in compiled RPZ zones. The repository never contains such lists or anything resembling them.

## Consequences

The public cannot audit those entries directly; that part of the trust rests on the list provider and the auditor, and the policy document must state that a restricted list is in use.
