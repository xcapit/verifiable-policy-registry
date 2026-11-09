# Incident and appeals runbook

*CC BY 4.0 · Proposal package for a school pilot · v0.3 preparation*

Procedures for the most common situations during the pilot. Response times are proposals to be confirmed in the scope charter.

## 1. A site is wrongly blocked (appeal)

| Step | Who | What | Target time |
| --- | --- | --- | --- |
| 1 | Teacher or school focal point | Uses the link on the block page and states the domain and why it is needed. No names or student details | — |
| 2 | Relayer (automatic) | Checks the appeal contains only domain, request and reason; publishes it and records its fingerprint in the public record | Immediate |
| 3 | Independent reviewer | Reviews the site and recommends accept or reject, with reasons | 2 working days |
| 4 | Governing signers | Accept by publishing a corrected policy version, or reject with a published reasoned decision | 5 working days from filing |
| 5 | Operator | Loads the corrected policy; confirms to the school | Same day as approval |

If an appeal is rejected, the decision and its reasons are public, and the same appeal can be filed again with new information. A school that disagrees can escalate to the ministry focal point and to the reviewer; the escalation route is defined in the scope charter.

**When the block page is unreachable**, appeals are accepted by the operator's support line and filed when the service is restored; the delay is recorded.

## 2. Emergency unblock

When a block prevents urgent access to education, health or safety information (for example a public-health site during an outbreak):

1. The school or ministry contacts the operator's support line.
2. The operator informs all three signers immediately.
3. Two signers approve an emergency version that excepts the domain, with a short validity (proposed: 7 days) and reason code "correction".
4. Within that validity, the normal appeal process decides whether the exception becomes permanent.

The emergency path never bypasses the signature requirement; it shortens the time, not the rule.

## 3. Emergency block

When a new threat (malware or phishing campaign) targets schools:

1. The operator proposes a version adding the domains, with reason code "new threat" and a short validity.
2. Two signers approve. The block is public with its reason, like any other.
3. The version expires unless renewed through the normal cycle.

Content categories other than security threats are not added through the emergency path.

## 4. A threat is not blocked (false negative)

1. Reported by the reviewer (test failure) or by a school.
2. The operator checks whether the domain is in the selected feeds and whether the school resolves through the pilot resolver.
3. If the feed is missing the domain, the operator proposes a local block (emergency block above). If the school bypasses the resolver, the provider is asked to fix redirection, and the school's attestation is revoked until a re-test passes.

## 5. Service incidents

| Incident | First action | Communication |
| --- | --- | --- |
| Both resolvers down | Restore; provider applies the fallback defined in the scope charter | Schools and ministry informed within 1 hour (proposed) |
| Public record unreachable | No action needed for filtering; queue publications | Noted on dashboard |
| Daily publication missed | Rerun the daily job; if a day cannot be published, record the gap | Noted on dashboard |
| Provider stops redirecting DNS | Provider fixes; reviewer re-tests; attestation revoked meanwhile | Ministry and Giga informed |

## 6. Security and privacy incidents

- **Personal data found in an export, log or public record:** stop publication, remove what can be removed off-chain, inform the data-protection focal point within 24 hours (proposed; national law may require less), and treat it as a stop condition. Data written to the public record cannot be erased; this is why the exporter is designed to never emit it.
- **Suspected key compromise of a signer:** the other two signers replace the key; any version published in the meantime is reviewed and, if needed, superseded.
- **Compromise of the operator's publishing key:** the governing institutions appoint a new publisher; summaries published by the compromised key are flagged.
- **Vulnerability report:** handled under [../../SECURITY.md](../../SECURITY.md).

## 7. Illegal content (for example child sexual abuse material)

The project never stores or shows such content. If someone encounters it through a pilot school, they report it to the national hotline (member of INHOPE) or to the IWF; the block page will carry the hotline link for the country (Planned, VPR-017). Domains confirmed as abusive are handled through the restricted list, never through a public policy entry that would point people to them.

## 8. Records

Every incident, its timeline and its resolution are recorded in an operator incident log shared with the signers. The log contains no browsing data and no personal data beyond the names of staff acting in their professional role.
