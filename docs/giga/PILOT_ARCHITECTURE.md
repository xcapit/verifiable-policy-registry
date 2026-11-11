# Pilot architecture

*CC BY 4.0 · Proposal package for a school pilot · v0.7.0*

This page describes what runs where during the pilot and how the system behaves when connectivity, power or a component fails. It is written for readers without blockchain background; the technical specification is in [../ARCHITECTURE.md](../ARCHITECTURE.md) and [../INTERFACES.md](../INTERFACES.md).

## What runs where

| Place | Component | What it does | Status |
| --- | --- | --- | --- |
| School | Nothing new | The school's router (or the provider) sends DNS questions to the pilot resolver. No software on devices | — |
| Connectivity provider | DNS redirection and blocking of external resolvers | Ensures school devices use the pilot resolver | Depends on the provider; Planned |
| Regional cloud or provider site | Two resolver instances with the compiled filter zone | Answers DNS questions, blocks domains in the policy, shows the block page | Designed (reference configuration); Planned M2 |
| Same site | Exporter | Turns each block into a count per school, day and category; discards everything else in memory | Planned (VPR-016) |
| Same site | Daily job | Aggregates counts, removes small cells, publishes the dataset and its fingerprint | Implemented (tools); scheduling Planned |
| Web | Block page and appeal relayer | Explains why a site is blocked and accepts appeals without requiring any account | Planned (VPR-017) |
| Public record | Policy registry and daily-summary anchor | Holds policy commitments, appeal hashes and daily roots | Implemented, not audited; local test chains only |
| Public record | EAS attestations | Would hold deployment, test and conformance attestation summaries | Schemas Defined; role-enforcing resolver Implemented (not yet registered); registration Planned (M2) |
| Web | Public dashboard | Shows the policy in force, attested schools and daily summaries | Planned (VPR-021) |

## Intended information flow

1. The governing institutions approve a policy version; its fingerprint, reason and expiry date are written to the public record.
2. The resolver loads the filter zone compiled from that exact document, and refuses a document whose fingerprint does not match.
3. For each blocked question, the Planned exporter would emit only `(school, day, category)`. Domain names, IP addresses and device identifiers would remain transient in the resolver process and would not be written to disk or exported; this has not been validated against a running resolver.
4. Each day, counts below the threshold are suppressed, the remaining counts are published, and their fingerprint is written to the public record.
5. The independent reviewer tests each school from inside its network and records the result in the public record.

## Connectivity and power assumptions

Candidate schools may have intermittent, low-bandwidth, satellite or power-limited connections. The design therefore assumes:

- **School side:** nothing stateful runs at the school. When the school is offline, nothing is filtered because nothing is reachable; when it is back, filtering resumes immediately. No data is queued at the school.
- **Latency:** resolvers are placed as close as possible to the schools' internet exit (the provider's point of presence or the nearest cloud region), cache answers within their validity, and serve stale answers when an upstream is slow (RFC 8767). The added latency per school is measured during onboarding.
- **Bandwidth:** the design redirects DNS and may add block-page traffic; its school-side overhead has not been measured. Exact figures are measured in the alpha (Unknown — input required, operator, M2).
- **Power:** a school losing power affects that school's router, local network and connectivity. The regional resolver site has a separate availability dependency on its hosting infrastructure.
- **The public record:** filtering never depends on it. If the public network is slow or unavailable, the resolver keeps enforcing the last verified policy and publication resumes later.

## Degraded modes

No degraded mode silently removes child protection or the ability to appeal. Each mode is visible to the operator. Where it affects schools, it is also reported to the governing signers and the ministry within the notification target set in the scope charter, and shown on the public dashboard once that exists (VPR-021, M3).

| Situation | Behaviour | Child safety | Appeals |
| --- | --- | --- | --- |
| One resolver instance down | The other instance serves all schools | Unchanged | Unchanged |
| Both resolver instances down | Schools lose name resolution (effectively offline). The scope charter decides whether the provider switches to a secondary protective resolver; an unfiltered fallback is not permitted in the pilot. If the service is paused, the pause is announced to the ministry and the schools | Kept, or service paused | Block page unreachable; appeals by email or phone to the operator's support line, recorded later |
| Public record unreachable | Last verified policy keeps running; publication of summaries and appeals is queued | Unchanged | Relayer accepts appeals and files them when the network returns; the delay is shown on the block page |
| Policy expires without renewal | Fallback defined in the scope charter (recommended: protective categories only, malware and phishing) | Core protection kept | Unchanged |
| Exporter or daily job fails | Filtering unchanged; no summary for that day; the gap is visible in the public record | Unchanged | Unchanged |
| Block page down | Blocks still applied; operator restores the page as priority | Unchanged | Support line as above |
| Provider stops redirecting DNS | Devices may bypass the filter. Reviewer bypass tests detect it; attestation revoked | Reduced; reported to the signers and the ministry, and shown on the dashboard once it exists | Unchanged |

## Policy and restricted lists

- Policies are written per scope (for example primary schools in one country), reviewed by the governing institutions and published in full, each blocked or excepted domain with a reason. See [../GOVERNANCE.md](../GOVERNANCE.md).
- Lists that cannot legally be published, such as the IWF list, would be obtained by the operator directly from the provider under its terms. Only a fingerprint is public, so anyone can see which list commitment was declared and when it changes, but not the list contents or whether the resolver actually used it. The compiler refuses to build a zone if the supplied list does not match the declared fingerprint.
- A fingerprint shows which list was declared; it does not by itself prove that the resolver applied it. That is checked by the reviewer's tests and the audit.

## Explicit boundaries

- Filtering is by domain name. Entries that are individual pages on otherwise legitimate sites need a different control (for example at the provider) and are outside this pilot.
- VPNs and devices configured to ignore network DNS can bypass the filter. This is reported, not hidden: the reviewer's attestation records whether bypasses were resisted.
- Further detail on threats: [../security/THREAT_MODEL.md](../security/THREAT_MODEL.md).
