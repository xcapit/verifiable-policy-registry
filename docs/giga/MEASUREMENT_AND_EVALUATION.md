# Measurement and evaluation

*CC BY 4.0 · Proposal package for a school pilot · v0.3.0*

How the pilot is evaluated, and what is deliberately not measured.

## What is never collected

**The proposed pilot prohibits collecting individual browsing histories for evaluation or any other purpose.** No evaluation question requires knowing which student or device visited which site, and none may be answered that way. This rules out logging queried domain names, retaining IP addresses, sampling traffic for "quality checks", or asking schools to export router logs. The current repository contains a no-logging reference configuration but no running resolver or exporter; conformance must be established before Stage 1. A request to collect such data is a stop condition (see [PILOT_READINESS.md](PILOT_READINESS.md)).

The designed exporter would emit only `(school_id, day, category)` events; the implemented aggregation tool turns them into counts and suppresses small cells before publication. The exporter is Planned (VPR-016). See [../PRIVACY_STATEMENT.md](../PRIVACY_STATEMENT.md) and [../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md).

## Indicators

| Area | Indicator | How it is measured | Target (proposed, to be agreed) |
| --- | --- | --- | --- |
| Protection | Schools with a valid independent test attestation | Reviewer's black-box tests from each school network, recorded in the public record | Alpha: at least 2 of 2–5 schools |
| Protection | Blocked categories actually blocked | Reviewer test set of synthetic and known-bad test domains per category | All test domains blocked |
| Protection | Bypass resisted | Reviewer tries external DNS, DNS-over-HTTPS and DNS-over-TLS from the school | All known bypasses fail, or failure reported |
| Over-blocking | Exceptions reachable | Reviewer checks every excepted domain in the policy | All reachable |
| Over-blocking (false positives) | Wrongly blocked reports | Appeals filed, accepted and rejected, from the public record | Reported, with response time |
| Under-blocking (false negatives) | Known-bad test domains not blocked | Only measurable on the reviewer's test sets; not measured on real traffic | Reported per test cycle |
| Availability | Resolver availability | External monitoring of the resolver endpoints (no query content) | Unknown — target set at Gate A from hosting and link conditions |
| Performance | Added DNS latency per school | Measured at onboarding and per test cycle by the reviewer kit | Unknown — input required (operator, M2) |
| Governance | Policy changes with required signatures and stated reason | Public record | 100% |
| Appeals | Time to a reasoned decision | Public record timestamps | Unknown — target set in the scope charter |
| Accessibility | Block page usable in the pilot language and with a screen reader; appeal possible without an account | Checklist in [LOCALISATION_AND_ACCESSIBILITY.md](LOCALISATION_AND_ACCESSIBILITY.md) | All items met |
| Privacy | Personal data in any export or public record | Reviewer and auditor checks | None |
| Verifiability | Daily summaries recomputed by a party outside the project | Independent run of `vpr verify-root` | At least once |
| Cost | Cost per school per month | [COST_MODEL_TEMPLATE.md](COST_MODEL_TEMPLATE.md) | Reported with evidence |

## Interpreting the daily counts

The daily counts show how often the filter blocked something in each category at each school. They are useful for operations and for showing that the system is working; they are **not** a measure of child safety outcomes, of how many children were protected, or of behaviour. Counts depend on device numbers, malware activity and school timetables, and a high count is not evidence of misconduct by anyone. Evaluation reports should not rank schools by counts.

Counts are of blocked queries, not of people: one device can generate many events. Suppression of small cells limits disclosure about individuals, not about small groups; see the re-identification analysis linked above.

## Evaluation questions for the alpha

1. Can schools be protected and independently attested within the operating conditions of the pilot country (connectivity, provider cooperation)?
2. How often is legitimate content blocked, and how quickly is it corrected?
3. Is the added latency acceptable on the slowest pilot links?
4. Can the governing institutions run the policy cycle (approval, renewal, appeals) without technical assistance?
5. What does it cost per school, and who would pay after the pilot?

Answers come from the indicators above, a short structured interview with each school focal point and each signer at the end of the alpha, and the operator's incident log. Interviews do not ask about individual students.

## Reporting

- Operational evidence (availability, latency, attestations, appeals, cost) is reported at Gate B and Gate C.
- An impact report over a full school term is planned for phase 2, from the public datasets only.
- Every figure in a report cites the public record entry or dataset it comes from.
