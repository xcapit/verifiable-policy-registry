# Policy governance

*CC BY 4.0*

This page covers who governs each **filtering policy**. How the open-source project itself is run is described in [GOVERNANCE.md](../GOVERNANCE.md) at the repository root.

## Roles

| Role | Who (proposed pilot; none confirmed) | Powers | Must not (enforcement noted) |
| --- | --- | --- | --- |
| Governor | Safe multisig 2-of-3: UNICEF Giga, Ministry of Education, independent reviewer | Publish policy versions, accept or reject appeals, rotate governor | Act with a single signature (holds only if the governor address is an m-of-n Safe; the registry accepts any address) |
| Operator | Xcapit | Run resolver, publish datasets and roots, attest deployments | Change policy (enforced by the registry); attest its own tests (enforced for attestations by `IssuerRoleResolver` once the schemas are registered; one institution using several addresses remains a governance matter) |
| Independent reviewer | Child-protection NGO or university | Third signer; test schools; attest tests; review appeals | Operate the resolver (by policy) |
| Auditor | Third party | Attest conformance to standards | Govern |
| Public | Anyone | Read everything, file appeals, recompute roots | — |

## Reason codes

Used in `publishPolicy(..., reasonCode, ...)` and in policy documents.

| Code | Meaning |
| --- | --- |
| 1 | `initial_policy`: first version for a scope |
| 2 | `scheduled_renewal`: re-signing before expiry, no content change |
| 3 | `appeal_accepted`: resolves an appeal (set `resolvesAppeal`) |
| 4 | `new_threat`: new malware/phishing category or feed |
| 5 | `legal_requirement`: change required by law (must cite it in the document) |
| 6 | `correction`: fixes an error in a previous version |

## Rules

1. Every local block and exception in a policy document states its reason.
2. Maximum validity per scope: 90 days in the pilot. Renewal is a signed act.
3. Appeals are answered within 5 working days (pilot target).
4. Restricted lists are referenced only by hash; their use is stated in the document.
5. The charter of each scope defines the fallback when a policy expires without renewal (recommended: protective-only categories: malware and phishing).
6. Key management: hardware wallets or passkey-based smart accounts for institutional signers; documented recovery; signer rotation via Safe and the two-step handover (`proposeGovernor`, then `acceptGovernor` by the new governor).

## Scope charter

Every scope has a charter, signed by all governor signers before its first policy version, and published with a hash in the policy document. It fixes at least:

- maximum validity, and the fallback when a version expires without renewal;
- **categories that may never be blocked as such**: education, health (including sexual and reproductive health information for the appropriate age), human rights, journalism, political information, and information for LGBTQ+ young people. Individual domains inside these areas can still be blocked only with a stated reason that the reviewer checks;
- the response time for appeals, and the external recourse path (below);
- the release policy for metrics (threshold, minimum cohort, category tiers, delay), taken from the DPIA ([privacy analysis](privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md));
- the identities of the issuers for each attestation role, recorded on-chain with `setIssuer`.

## Emergency changes

- **Emergency unblock.** When a block clearly harms access to education or safety information, any signer may propose a version that removes it, with reason code 6 (`correction`) and a short validity (proposed: 7 days). It still needs the threshold of signatures. The usual review happens afterwards, and the short validity forces it.
- **Emergency block.** This applies to an active threat, such as a malware campaign. Reason code 4 (`new_threat`), short validity, and the same threshold.
- An emergency never changes the categories that may never be blocked.

## Escalation and external recourse

A rejected appeal records the hash of a reasoned decision that is published off-chain. The person who appealed, or anyone else, can resubmit the appeal in a new round with new arguments. If the governor rejects it again, the charter names an external body that can review the case, such as an ombudsperson, a data-protection authority or a child-rights body depending on the country. The governor commits to publishing that body's conclusion. The protocol records the process; it cannot force the outcome ([threat model T16](security/THREAT_MODEL.md)).

## Monitoring governance changes

Changes to who governs are as important as changes to what is blocked. Dashboards and the deployment manifest (VPR-049) alert on `GovernorChanged`, on changes of Safe owners or threshold, and on `IssuerSet`. Such changes are announced publicly with a reason. Proposed: a waiting period of 7 days for non-emergency signer changes, during which they can be contested.

