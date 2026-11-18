# ADR-0015: Make unanswered appeals visible, and bound appeal spam

- Status: Proposed (for the M1 review; the reporting rules are to be implemented with the dashboard, the registry change is not implemented)
- Date: 2026-11-18

## Context

Property P5 (contestability) guarantees three things:
- anyone can file an appeal;
- each appeal ends in at most one final outcome;
- a rejection carries a reason hash.

It does not guarantee that an appeal is answered. The white paper says so ("the contract does not bound the time to respond"), and GOVERNANCE sets a pilot target of five working days in the scope charter. A governor that ignores appeals is not detected by any check today. It is visible only to someone who reads the `AppealFiled` events and notices that no `AppealResolved` follows.

Filing is open, so that the appeal channel cannot be censored (T23). The filer is not recorded, so that appellants are not linked to their appeals. The nonce of appeal format 3 stops a third party from guessing and pre-filing a document (T25). On OP Mainnet, though, nothing stops anyone from filing many bare hashes. At the fees measured in [BENCHMARKS](../benchmarks/BENCHMARKS.md#21-one-year-of-one-scope-with-the-l1-data-fee), a filing costs about 7.6 × 10⁻¹⁰ ETH in L1 and L2 base fees (median; priority fees excluded), so ten thousand filings cost well under one US dollar. Any rule that makes ignoring appeals costly for the governor also makes appeal spam costly for the governor. The two problems have to be decided together.

## Decision

### 1. Reporting rules, off-chain, from the dashboard (VPR-021, VPR-076)

- **Substantiated appeal.** An appeal counts as substantiated when its document is available to verifiers within 3 days of filing, through the relayer or from the appellant. The document must:
  - hash to the on-chain `documentHash`;
  - validate as `vpr-appeal/3`;
  - name the appeal's scope.

  Otherwise the appeal is **unsubstantiated**. It is shown, but not counted against the governor. The governor may reject it with a published standard reason ("document not provided").
- **Overdue appeal.** A substantiated appeal is overdue when it is still open after the scope charter's response time, stated in calendar days, because block time is calendar time. The pilot target of 5 working days becomes 7 calendar days.
- **Publication.** For each scope, the dashboard shows the open, overdue and unsubstantiated appeals and the median time to resolution. The evaluation plan reports the share of appeals answered on time. An overdue appeal is a public, dated fact about a named governor, of the same kind as an expired policy.

These rules need no contract change. They are checks over public events and documents, like the content-hash check.

### 2. Bounded on-chain pressure, only together with anti-spam

The obvious contract change is to refuse new versions while an overdue appeal is open. It is not adopted on its own, because it turns spam into a lever:
- the contract cannot tell a substantiated appeal from a bare hash;
- so an attacker filing bare hashes could force the governor to reject them, one Safe transaction per batch, before any new version, including an emergency block.

For the next registry, which is redeployed together with ADR-0010 and ADR-0011, the decision is:
- **Batch rejection.** Add `rejectAppeals(bytes32[] appealIds, bytes32 reasonHash)`, so that one Safe transaction rejects many unsubstantiated appeals. This bounds the governor's cost of spam to a few transactions, whatever the number of filings. It is needed under every option below.
- **Renewal gate, deferred.** A gate is reconsidered only once filings are rate limited without identifying the filer. Under it, `publishPolicy` would refuse every reason code except 3 (appeal accepted) while an appeal older than the scope's response window is open. Two approaches to the rate limit are being studied:
  - relayer-paid filings with rate limits (VPR-017), with direct filing kept as a censorship-resistant fallback;
  - Rate-Limiting Nullifiers or anonymous credentials (VPR-078), which bound filings per member per epoch without revealing the member. They need a membership set, and how to admit members without excluding anyone, and without letting one person create many identities, is itself the open question.

### 3. Anti-spam now

The defences against spam today are:
- the format-3 nonce;
- gas paid by direct filers;
- the relayer's planned rate limit (VPR-017);
- the substantiation rule above, which makes bare hashes cost the attacker gas without creating an obligation that counts against the governor.

## Consequences

- **Ignoring appeals becomes visible.** It is not yet prevented. Like expiry, it relies on the public record: a governor that does not answer has its overdue appeals on the dashboard.
- **Spam stops counting.** Bare hashes are cheap to file, but they no longer count against the governor or in the metrics. Batch rejection, once deployed, clears them in one transaction.
- **Documents must be available to verifiers.** This needs the relayer's storage and retention rules for appeal documents, which T24 and the DPIA already require. Appeal documents carry no personal data fields (I9), but their free text needs moderation before it is shown publicly.
- **An open question stays open.** Rate limiting without identifying the filer is a research item, not a decision. It is stated as such in the threat model (T25) and the claims ledger (C60).

## Maintainer's recommendation for the M1 review

- Adopt the reporting rules of §1 with a 3-day substantiation window and a 7-day pilot response time.
- Include `rejectAppeals` in the single redeployment recommended in ADR-0011.
- Defer the renewal gate until VPR-017 is running and VPR-078 has a result.

## Alternatives considered

- **An appeal that times out counts as accepted.** Anyone could then unblock anything by spamming. Rejected.
- **A cap on open appeals per scope.** Spam would fill the cap and lock out real appellants, which is a denial of service on the recourse channel. Rejected.
- **A deposit or bond per filing.** It excludes students and teachers, the people the channel is for. Rejected, except as a relayer-paid cost that the appellant never sees.
- **Relayer-only filing.** Spam can be rate limited, but the relayer becomes a censor (T23). Rejected: direct filing stays open.
- **Recording the filer to rate limit by address.** Appellants could be linked to appeals, and new addresses cost nothing. Rejected.
