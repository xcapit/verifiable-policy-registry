# ADR-0012: An independent test remains valid across renewals that do not change the rules

- Status: Accepted (rule and tool support implemented; dashboard check planned)
- Date: 2026-11-11

## Context

INTERFACES I8 counted a school as protected only with a valid `VPR.IndependentTest.v1` for the policy version in force. A scheduled renewal (reason code 2) re-signs a policy before it expires without changing what it blocks, but it is a new version, so under that rule every renewal invalidated every school's test.

The one-year workload in [BENCHMARKS §2.1](../benchmarks/BENCHMARKS.md#21-one-year-of-one-scope-with-the-l1-data-fee) shows the cost. With 50 schools and a renewal every 30 days, the reviewer issues 1 000 attestations a year. They are 93 % of all execution gas, and most of them re-certify an unchanged rule set. Beyond gas, re-testing every school every month is a load on the reviewer that does not buy evidence.

The reason code cannot carry the decision by itself. The registry stores reason codes but not documents, so a governor could label a change of content as a renewal.

## Decision

- **Rules digest.** For each policy document, tools compute `keccak256` of its canonical form without the three keys a renewal may change: `version`, `reason_code` and `valid_days` (INTERFACES I1). Everything that determines what is blocked or allowed stays in the digest: scope, profile, categories, feed hashes, threat feeds, local blocks, exceptions and the restricted-list commitment.
- **Reporting rule.** A school counts as protected with a valid, unrevoked independent test for the version in force, or for an earlier version of the same scope with the same rules digest (INTERFACES I8). The test's own `validUntil` and revocation still apply, so a test still has to be renewed on the reviewer's schedule.
- **Renewals.** A version with reason code 2 must keep the rules digest of the version it renews (GOVERNANCE). The digest is computed from the published documents, whose hashes are on-chain, so anyone can check this. A renewal label on a version whose digest changed does not carry tests over, so the label cannot be abused to keep tests alive.
- **Unchanged.** The contracts do not change; `IssuerRoleResolver` does not check `policyVersion` (INTERFACES I8). Deployment attestations by the operator stay per version, because they state that the resolver loaded that version's zone.

## Consequences

- **Fewer re-tests.** Reviewer attestations scale with the number of rule changes, not with the number of versions. In the benchmark workload that is 400 instead of 1 000 a year.
- **No extra trust.** The protection claim still rests on a test of the same rules that are in force. Only the label of the version changes. A verifier, or the planned dashboard, must fetch both documents and compare digests; that is one more off-chain check, of the same kind as the content-hash check.
- **Detection, not prevention.** A governor that changes the rules in a version labelled as a renewal is not stopped. It is detected, and the schools tested under the old rules stop counting as protected.

## Alternatives considered

- **Keep the rule and renew less often.** Longer validities weaken expiry (P4), which exists to force periodic review. Rejected as the only lever, though a charter may still choose longer renewals.
- **Trust the reason code.** A governor could carry tests over a real change of rules. Rejected.
- **Use the compiled zone hash.** The zone embeds the version as its SOA serial and in its header, so it changes on every renewal, and it also depends on feed contents fetched at compile time. Rejected.
- **Check it on-chain.** That would need the document or its digest on-chain, and a resolver that checks attestations against versions. It adds contract complexity for a check that anyone can already run on public data. Not adopted now.
