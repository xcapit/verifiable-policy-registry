# Threat model

*CC BY 4.0 · v0.3 · Covers backlog item VPR-003 for the components that exist or are designed. To be reviewed at Gate A (ROADMAP M1) and after every interface change. Residual-risk ratings: **L**ow, **M**edium, **H**igh, judged for a pilot with real schools after the planned mitigations, not for the current prototype.*

## 1. Assets

| Asset | Why it matters |
| --- | --- |
| A1 Children's browsing | Must never be recorded, inferred or exposed |
| A2 Integrity of the policy in force | Decides what children can reach; a target for censorship |
| A3 Availability of safe browsing | Schools depend on name resolution |
| A4 Integrity of published metrics | Basis of claims to donors and governments |
| A5 Restricted lists (e.g. IWF) | Disclosure would cause harm and breach terms |
| A6 Governor and issuer keys | Control A2 and the attestation record |
| A7 Appeal channel | The recourse against over-blocking |
| A8 Credibility of attestations | "This school is protected" must mean it |

## 2. Actors and trust

| Actor | Assumed behaviour |
| --- | --- |
| Students and teachers | Honest users; some will try to bypass the filter |
| School network staff | Mostly honest; may misconfigure |
| Connectivity provider (ISP) | Honest-but-curious; enforces DNS routing under contract |
| Operator (resolver, exporter, publisher) | **Not trusted**: considered both honest-but-curious and malicious |
| Proposed governor signers (Giga counterpart, ministry, reviewer; all unconfirmed) | Security analysis assumes at least one acts in the interest of children and the public; any threshold coalition may collude |
| Independent reviewer | Trusted to test honestly (P6); a single point of trust, mitigated by rotation and publication |
| Auditor | Trusted for the scope audited |
| Relayer (block page, appeals) | Not trusted for integrity; can censor appeals it handles |
| L2 sequencer and RPC providers | Not trusted for liveness or for honest reads |
| CI and release accounts | Trusted only as far as branch protection and review allow |
| Public verifiers | Untrusted; may be adversarial (re-identification) |

## 3. Data flow and trust boundaries

```
[device] --DNS--> [ISP] --> [resolver | exporter]  ==TB1==>  [aggregator/publisher]  ==TB2==>  [L2: registry, anchor, EAS]
                                   |                                 |                          ^
                              TB0: client IP and qname          TB3: public releases       [governor Safe] [reviewer] [auditor]
                              never cross this boundary         (CSV/JSON, mirrors)        [relayer] <- appeal documents
```

- **TB0.** Client addresses and queried names exist only inside the resolver process, apart from a declared operational buffer.
- **TB1.** Only `(unit_id, day, category)` crosses it.
- **TB2.** Only roots, hashes, attestations and appeal hashes are written on-chain.
- **TB3.** Only cells with a count of at least *k* are published.

## 4. Threat register

Verification methods: **T** automated test in this repository, **D** demonstrator, **R** reviewer black-box test, **A** external audit, **G** governance procedure, **—** none yet.

| ID | Component | Threat | Mitigation | Residual | Owner | Verified by |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Resolver | Operator logs queries (honest-but-curious) | `log-queries: no` in the reference config; RFC 8932 statement; configuration hash in the deployment attestation; audit | M | F. Schillage | A, R (config) |
| T02 | Resolver | Operator enforces a policy other than the one in force | Zone header carries `contentHash`; sync daemon refuses mismatches (VPR-015); reviewer tests | M | F. Schillage | R, D (zone evaluation) |
| T03 | Resolver | Split-view: correct for test traffic, different for students | Tests from inside school networks, unannounced, from ordinary devices; canaries (Designed) | H | Reviewer | R |
| T04 | Resolver | Resolver unreachable (outage, satellite link loss) | Two instances; serve-stale (RFC 8767); scope-charter fallback; never an unfiltered fallback by default | M | F. Schillage | R, G |
| T05 | Network | Bypass through external resolvers, DoH or DoT | Provider blocks port 53/853 to others and known DoH endpoints; `bypassResisted` in the attestation | M | Provider, reviewer | R |
| T06 | Network | Bypass through VPNs, tunnels, local device configuration | Not preventable at the DNS layer; reported, not hidden | H (accepted) | — | R (reported) |
| T07 | Network | Encrypted Client Hello | No effect on DNS-level filtering when clients use the network resolver | L | — | R |
| T08 | Network | Captive portals or provider transparent DNS proxies interfere | Onboarding checklist; latency and resolution tests at onboarding | M | Provider | R |
| T09 | Exporter | Emits more than `(unit, day, category)` | Aggregator accepts only that header (`read_events` rejects extra fields); exporter and its unit tests are Planned (VPR-016) | L | M. Bruno | T (aggregator boundary only) |
| T10 | Aggregator | Omits, truncates or fabricates events | **Not mitigated cryptographically.** Reviewer tests; canaries (Designed, VPR-038); audit | H | Operator, reviewer | R, A |
| T11 | Aggregator | Publishes or leaks suppressed cells | No suppression count published; errors never echo values; privacy regression tests | L | F. Arduh | T |
| T12 | Publisher | Alters figures after publication | Write-once root per scope and day; anyone recomputes it | L | — | T, D |
| T13 | Publisher | Serves different datasets to different people | Root on-chain; anyone holding a copy can recompute it; mirrors | M | Operator | D |
| T14 | Publisher key | Compromised publisher anchors false roots | Governor rotates the publisher (`setPublisher`); roots are public and contestable | M | Governor | T, G |
| T15 | Governor | One signer acts alone | Proposed m-of-n Safe deployment; the registry itself trusts one governor address | L after deployment; not applicable to the undeployed prototype | Signers | G (Planned) |
| T16 | Governor | Majority collusion: censorship, rejected appeals, reviewer replaced | Public versions with reasons, mandatory expiry, reasoned rejections on-chain, alerts on Safe owner changes (VPR-049); charter list of never-blocked categories; external recourse (§5) | M | All signers | G |
| T17 | Governor keys | Key loss or theft | Hardware or passkey custody; documented recovery; rotation through Safe and `setGovernor` | M | Signers | G |
| T18 | Registry | Scope squatting under a canonical name | A deployment manifest pins chain, registry, scope and expected governor (VPR-049, Planned). `createScope` requires the caller to equal the governor argument but does **not** reserve human-readable scope names; a first caller can occupy a `scopeId` under its own address | H until manifest discovery and a scope-registration procedure exist | M. Nivoli | T (caller/governor equality only) |
| T19 | Anchor | First-caller claim of a scope | Removed: the publisher is appointed by the registry governor | L | M. Nivoli | T, D |
| T20 | Anchor | Internal node or other day presented as a row | `verifyRow` hashes rows; day in leaf | L | M. Nivoli | T, D |
| T21 | Attestations | Operator certifies its own deployment as tested | One role per address is recorded in the registry; an EAS schema resolver enforcing those roles is Planned (VPR-012) | H until the resolver is deployed; M after planned mitigation | M. Nivoli | T (role mapping only) |
| T22 | Reviewer | Dishonest or negligent reviewer | Published test summaries; reports to the governor; rotation; second reviewer for sampling (to agree) | M | Governor | G |
| T23 | Relayer | Refuses or delays appeals | Anyone can file a document hash directly; response time in the charter; escalation path | M | Operator | G |
| T24 | Appeals | Abusive text or personal data on-chain | The contract accepts only document hashes. Relayer validation, access rules, retention and off-chain takedown are Planned and must be fixed in the DPIA | L on-chain; M off-chain until procedures exist | Operator | T (on-chain boundary only) |
| T25 | Appeals | Appeal spam | Gas cost for direct filings; relayer rate limits | L | Operator | — |
| T26 | L2 | Sequencer censors governance or appeal transactions | Forced inclusion through L1 (runbook, Planned); filtering unaffected | M | M. Nivoli | — |
| T27 | L2 | Reorganisation before finality | Dashboard shows finality state; actions wait for finality (Planned) | L | Operator | — |
| T28 | L2 | RPC provider returns a false view | Several RPC providers; verifiers compare (Planned) | M | Operator | — |
| T29 | L2 | Gas price spike blocks anchoring or appeals | Small, constant transaction count; funded relayer; delayed anchoring tolerated | L | Operator | — |
| T30 | Data availability | Policy document or dataset unavailable | Mirrors on independent hosts; unavailability is visible | M | Operator | G |
| T31 | Restricted list | Declared but not enforced, stale, or wrong | Compile-time hash check (implemented); confidential auditor verification (Planned) | M | Auditor | T, A |
| T32 | Restricted list | Disclosure via zone labels or repository | Restricted entries are unlabelled in compiled zones and list contents are never committed to the repository; only an unsalted hash commitment is published | L against accidental labels; candidate-list testing remains possible | — | T |
| T33 | Metrics | Re-identification by joining releases with public data | See the [privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md); release policy for small schools | M | D. Truyol | — |
| T34 | Policy | Over-blocking of education, health, LGBTQ+, political or journalistic content | Reasons per entry; exceptions; charter never-block list; reviewer checks exceptions are reachable; appeals; expiry | M | Governor, reviewer | R, G |
| T35 | Tooling | Policy compiled without promised protection (missing feed) | Compiler fails closed | L | M. Bruno | T |
| T36 | CI and release | Compromised CI or maintainer account pushes malicious code | Branch rulesets (no force push, required CI); two approvals for contracts; signed-off commits; tagged releases | M | F. Boiero | G |
| T37 | Dependencies | Malicious or vulnerable package | Lockfile; Dependabot; review of updates | M | F. Schillage | G |

## 5. Recourse beyond the governor

A colluding majority can reject an appeal. The design makes this visible: the rejection reasons are hashed on-chain and published. What it cannot provide is a remedy. The scope charter therefore names an external recourse path, such as a national ombudsperson, a data-protection authority or a child-rights body depending on the country, and commits to publishing the outcome. Choosing that path is a decision for the deploying partners ([open questions](../giga/OPEN_QUESTIONS_FOR_GIGA.md)).

## 6. Non-goals and accepted risks

- Filtering against users who deliberately use VPNs or their own devices' DNS (T06).
- Proving on-chain that the resolver behaved correctly at runtime (T03, T10).
- Protection against a compromise of the cryptographic primitives or of the L2 itself.
- Any form of per-user monitoring: the system is designed so that it cannot provide it.
