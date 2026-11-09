# Privacy and re-identification analysis

*CC BY 4.0 · v0.3 · Owner: Diana Truyol (impact and privacy evidence), with Fernando Boiero. This document is a technical analysis, not a legal opinion. Compliance with data-protection law depends on the country and is assessed in the DPIA with the deploying partner (ROADMAP M1).*

## 1. Designed data inventory and retention

This table describes the target deployment, not current runtime evidence. The repository implements the aggregation and commitment path, contains a no-logging resolver configuration fragment, and does not contain a running resolver or exporter. Rows concerning those components remain **Designed** or **Planned** until M2 and require Gate A DPIA decisions.

| Data | Where it exists | Processed for | Retained | Published | Leaves the resolver process? |
| --- | --- | --- | --- | --- | --- |
| Client IP address | Resolver memory | Answering the query; access control | Not written to disk; at most within the declared operational buffer | Never | No |
| Queried name | Resolver memory | Answering; matching the zone | As above | Never | No |
| Device identifiers (MAC, hostname) | Not seen by a recursive resolver behind the school router | — | — | Never | No |
| Timestamp of a query | Resolver memory | Operation | As above | Never; only the UTC date survives | Only as a date |
| Block event `(unit_id, day, category)` | Exporter → aggregator | Aggregation | Until the daily release is built and committed (retention period to be fixed in the DPIA) | Never individually | Yes |
| Event log commitment `C_L` (Designed) | Aggregator; on-chain | Binding the release to the log | Permanent on-chain | Yes (hiding commitment) | Yes |
| Daily release: cells with count ≥ *k* | Public mirrors; root on-chain | Impact reporting | Permanent | Yes | Yes |
| Suppressed cells and their number | Aggregator memory only | — | Not retained after the release | **Never** | No |
| Policy documents | Public mirrors; hash on-chain | Transparency | Permanent | Yes | n/a |
| Appeal documents | Planned relayer; hash on-chain | Recourse | Retention and access policy to be fixed in the DPIA; removable off-chain | Unknown — Gate A decision; only the hash is necessarily public | n/a |
| Reviewer test reports | Shared with the governor; hash on-chain | Attestation | Per charter | Summary only | n/a |
| Operator and signer addresses | On-chain | Accountability | Permanent | Yes | n/a |

**Excluded by the design:** retained browsing histories, per-device or per-user identifiers, names or contact details of students, page content, URLs below the domain, and location beyond the public school identifier. This is not yet an observed property of a deployed system.

**Processed transiently:** a recursive resolver necessarily sees client IP addresses and queried names. This is personal-data processing even if nothing is retained, and the privacy statement says so ([PRIVACY_STATEMENT](../PRIVACY_STATEMENT.md)).

## 2. Public fields and their disclosure

| Field | Purpose | What it discloses | Risk |
| --- | --- | --- | --- |
| `unit_id` | Join with Giga Maps; per-school accountability | That a specific school uses the service | Institutional, intended |
| `day` | Daily commitments | Activity on a day, including weekends and holidays | Activity on unusual days can single out events (§4) |
| `category` | Impact by threat type | What kind of content was blocked | Sensitive categories (adult, self-harm) reveal behaviour of a group |
| `count` (≥ *k*) | Impact | Volume of blocked queries | Correlates with school size and with individual behaviour (§3) |
| Release root, dataset URI | Integrity | Nothing beyond the release | Low |
| `C_L` | Binding (Designed) | Number of events *m* in the day | Low; total volume per scope and day |

## 3. What the threshold does and does not protect

The threshold *k* counts **events**, not people. One device that retries, prefetches or repeatedly reloads a blocked page can produce ten or more events alone. A published cell of 40 blocks in a sensitive category can therefore describe a single child. The threshold prevents the publication of small counts. It does not give *k*-anonymity in the sense of Sweeney (2002), where each released record is indistinguishable among at least *k* individuals. It does not give differential privacy either.

What it does protect against:
- reading a count of 1–9, which in a small school could be traced to a person through local knowledge;
- inferring the presence of rare categories at a school from low counts.

## 4. Attacks with auxiliary data

| Attack | Auxiliary data | Effect | Mitigation |
| --- | --- | --- | --- |
| Small-school inference | Giga Maps school size, enrolment | A cell at a school with 15 pupils describes a small group | Minimum cohort size for publication (§5) |
| Calendar inference | School calendars, holidays, exam dates | A cell on a day the school is closed points to staff or a specific event | Publish only on school days, or coarsen to weeks |
| Incident correlation | Local news, public incidents | A spike in a category after a known incident attributes behaviour to a group | Delayed release; category merging |
| Category rarity | Rarely used categories | A non-zero published cell in a rare category is itself the signal | Merge sensitive categories into a single published "other protective" category |
| Repeated observation | Successive daily releases | Patterns over weeks single out persistent behaviour | Release budgeting; weekly aggregation; differential privacy for repeated releases |
| Differencing | Overlapping aggregates (e.g. daily plus weekly) | Subtracting releases recovers suppressed values | Never publish overlapping aggregates without a formal method (DP) |

The current release is one non-overlapping table per day, and the number of suppressed cells is not published. That closes differencing between releases, but not the auxiliary-data attacks above.

## 5. Decision framework for release controls

No single value of *k* is safe everywhere, and this document does not claim one. The release policy for a scope is fixed in its DPIA from the following rules. The parameters are to be set with pilot data and reviewed after the alpha (Gate B):

1. **Minimum cohort.** A unit is published only if its population (pupils plus staff) is at least *N_min*. Below that, its events are folded into a regional aggregate.
2. **Category tiers.** Protective categories (malware, phishing) can be published daily per school. Sensitive categories (adult, self-harm, violence) are published only weekly or regionally, or are merged into one category.
3. **Delayed release.** Releases are published with a delay of *d* days, so that they cannot be matched with live events.
4. **No overlapping aggregates.** Daily and weekly figures for the same cells are never both published, unless the release uses differential privacy with a documented budget.
5. **Differential privacy** becomes necessary when releases overlap, are requested adaptively, or concern populations below *N_min*. Its noise must be verifiable (white paper §11.3).
6. **Review trigger.** Any change of *k*, *N_min*, tiers or delay is a governance change, published with a reason code.

## 6. Small schools and sparse categories

Small schools are a foreseeable pilot condition. For them, the daily per-school release is the main risk. In the proposed alpha (2–5 schools), the starting design is: protective categories daily, sensitive categories weekly and merged, and no publication for schools below *N_min* until the DPIA sets it. These are design inputs, not approved defaults.

## 7. Automated privacy regression tests

`tools/tests/test_privacy.py` (run in CI):
- the threshold boundary, where *k* is published and *k* − 1 is not;
- no suppressed cell, category or count appears in the CSV or JSON outputs, nor the word "suppressed";
- the toolkit does not return the suppression count;
- error messages never echo values, categories or units;
- malformed counts fail safely;
- event input with extra fields (for example an IP column) is rejected;
- output ordering does not depend on input order;
- the demonstrator's output files contain no suppressed cell.

Not testable in this repository: the resolver's actual logging behaviour, memory handling and operational buffer. These are verified by configuration review, the auditor and the RFC 8932 statement.

## 8. Residual risks

- Group inference from published cells at small schools: **Medium** until the release policy (§5) is applied.
- Operator access to transient query data inside the resolver: **Medium**, controlled by configuration, audit and least privilege, not by cryptography.
- Long-term pattern analysis over many releases: **Medium**, until weekly aggregation or DP is adopted for sensitive categories.
