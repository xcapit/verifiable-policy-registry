# ADR-0016: A policy beacon in the zone, queryable from inside the network

- Status: Accepted for the unsigned beacon (implemented in `vpr compile-rpz --beacon` and `vpr check-beacon`); Proposed for a signed beacon and per-version canaries (for the M1 review)
- Date: 2026-11-19

## Context

Every check that VPR offers today looks at the ledger: which version is in force, who approved it, when it expires. Nothing lets a client inside a school ask the resolver which policy it is enforcing now.

The zone header names the scope, the version and the content hash (INTERFACES I4), but it is a comment in a file that clients never see. Between two reviewer tests, three failures go unnoticed:
- a sync daemon that stops and keeps serving an old or expired version (VPR-015);
- a school whose resolver loaded another scope's zone;
- a device that does not use the filtering resolver at all (A7).

The reviewer's black-box tests catch these, but only periodically and at a cost.

## Decision

**What the zone carries.** `vpr compile-rpz --beacon <domain>` adds one RPZ local-data record to the zone, for a domain the operator controls:

```
_vpr-policy.<domain> TXT "v=vpr1" "scope=<scope>" "version=<n>" "content=0x<contentHash>" "rules=0x<rulesDigest>"
```

Any client on the network can query it: `dig +short TXT _vpr-policy.<domain>`.
- The label starts with an underscore, so no blocked or excepted domain (I1) can collide with it. In RPZ an exact owner name takes precedence over wildcards, so the record holds even if `<domain>` is listed.
- Each field is its own character-string, well under 255 bytes.
- The beacon carries no zone hash. It cannot: the hash would be computed over a zone that contains it. The deployment attestation (I8) carries the zone hash.
- The beacon is opt-in. Zones compiled without `--beacon` are unchanged, byte for byte.

**How it is checked.** `vpr check-beacon <policy> (--txt <answer> | --zone <file>) [--version N] [--content-hash H]` compares the answer with the policy document that should be in force, and optionally with the version and content hash in force on-chain. Its exit codes:
- 0 when every field matches;
- 1 on any mismatch, or when no beacon answers;
- 2 when the beacon is malformed: an unknown format, or a missing, repeated or out-of-syntax field.

**How evaluation treats it.** `evaluate_zone` still fails closed on records it does not understand. It accepts the well-formed beacon and nothing else outside the CNAME triggers. The beacon is local data, so it changes no blocking decision. A test checks that evaluation is identical with and without it.

**What a missing beacon means.** If a school's zone has a beacon and a device gets no answer, the device is probably not using the filtering resolver. Any party can run that check without special access: the school, the dashboard, the reviewer kit, or a connectivity probe such as Giga Meter.

**Tested against a resolver.** The record was served by Unbound 1.25.0 from a zone compiled by `vpr compile-rpz --beacon`, and `vpr check-beacon` on the `dig` answer matched. The run was manual and local. Running it in CI needs the pinned resolver container (VPR-055).

## Consequences

- **Cheap, continuous detection of three failures:**
  - a stale zone: the version or content hash differs from the one in force;
  - a wrong scope;
  - a client that bypasses the resolver: no answer.
- **The beacon is a self-report.** The operator writes the zone. An operator who misreports on purpose can serve a correct beacon and a different zone. The beacon detects errors, not lies. Behaviour is still checked by the reviewer's tests (P6). Documents must never present a matching beacon as proof that the policy is enforced.
- **No new data is exposed.** Every field is already public on-chain or in the published document. A client learns that the network is filtered and under which public policy, which the block page already tells it.
- **The zone hash of a deployment changes when the beacon is added.** Deployments that adopt it publish the new hash in their deployment attestation, as for any zone change.

## Proposed for the M1 review

1. **A signed beacon.**
   - The beacon adds `sig=<signature>`, an EIP-191 signature by the operator's publishing key over the other fields and the zone hash.
   - It still does not stop an operator from misreporting. It turns a misreport that is caught later into a signed false statement, which is evidence of misconduct and not just a configuration error.
   - It needs a decision on which key signs, and on whether the signature covers the zone hash, which the deployment attestation already records (VPR-080).
2. **Per-version canaries (VPR-038).**
   - Each version blocks a canary name derived from its content hash, so that the reported version is also observable as behaviour.
   - The reviewer checks that the beacon reports version *n* and that the canary of version *n* is blocked.
   - This is still within the operator's control, but a consistent misreport must then reproduce behaviour as well as text.

## Alternatives considered

- **Serve the RPZ zone itself to clients** (AXFR, or a SOA query on the policy zone). This exposes the whole zone, including restricted entries in clear (ADR-0008). Rejected.
- **A beacon under a reserved name** (`.invalid`, or a made-up name under `.arpa`). Some operating systems and stub resolvers never send `.invalid` queries (RFC 6761), and names under `.arpa` are not the project's to assign. Rejected in favour of a domain the operator controls, such as the block page host.
- **An HTTP endpoint on the block page** (for example `/.well-known/vpr-policy`). It can be added, but it answers over HTTP, not over the DNS path that enforcement uses, so it cannot tell whether the client is using the resolver. Not adopted as the beacon.
