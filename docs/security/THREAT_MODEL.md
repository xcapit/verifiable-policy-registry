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
- **TB1.** Only `(unit_id, day, category)` crosses it. The aggregator enforces this on the header and on content: units and categories must be identifiers, so domains, addresses and free text are rejected (implemented). What the exporter actually emits is not yet implemented or tested (VPR-016).
- **TB2.** Roots, hashes, attestations and appeal hashes are written on-chain. Free text reaches the chain only through the governor-set policy `uri` and the publisher-set `datasetUri`, which are not length-bounded (T43).
- **TB3.** The tools publish only cells with a count of at least *k*. The root does not commit to *k*, so a publisher could anchor small cells; honest verifiers detect this with `vpr verify-root --k` (T44).

## 4. Threat register

Verification methods: **T** automated test in this repository, **D** demonstrator, **R** reviewer black-box test, **A** external audit, **G** governance procedure, **—** none yet.

| ID | Component | Threat | Mitigation | Residual | Owner | Verified by |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Resolver | Operator logs queries (honest-but-curious) | `log-queries: no` in the reference config; RFC 8932 statement; configuration hash in the deployment attestation; audit | M | F. Schillage | A, R (config) |
| T02 | Resolver | Operator enforces a policy other than the one in force, or substitutes feed contents | Zone header carries `contentHash`, but it is self-asserted and the policy hash does not bind feed contents; binding feeds and the produced zone is Planned (VPR-065); sync daemon refuses mismatches (VPR-015); reviewer tests | M | F. Schillage | R, D (zone evaluation) |
| T03 | Resolver | Split-view: correct for test traffic, different for students | Tests from inside school networks, unannounced, from ordinary devices; canaries (Designed) | H | Reviewer | R |
| T04 | Resolver | Resolver unreachable (outage, satellite link loss) | Two instances; serve-stale (RFC 8767); scope-charter fallback; never an unfiltered fallback by default | M | F. Schillage | R, G |
| T05 | Network | Bypass through external resolvers, DoH or DoT | Provider blocks port 53/853 to others and known DoH endpoints; `bypassResisted` in the attestation | M | Provider, reviewer | R |
| T06 | Network | Bypass through VPNs, tunnels, local device configuration | Not preventable at the DNS layer; reported, not hidden | H (accepted) | — | R (reported) |
| T07 | Network | Encrypted Client Hello | No effect on DNS-level filtering when clients use the network resolver | L | — | R |
| T08 | Network | Captive portals or provider transparent DNS proxies interfere | Onboarding checklist; latency and resolution tests at onboarding | M | Provider | R |
| T09 | Exporter | Emits more than `(unit, day, category)`, or a domain or address inside those fields | Aggregator accepts only that header, exactly three fields per row, and identifier-only units and categories (tested); exporter and its unit tests are Planned (VPR-016) | L | M. Bruno | T (aggregator boundary only) |
| T10 | Aggregator | Omits, truncates or fabricates events | **Not mitigated cryptographically.** Reviewer tests; canaries (Designed, VPR-038); audit | H | Operator, reviewer | R, A |
| T11 | Aggregator | Publishes or leaks suppressed cells | No suppression count published; errors from the tools do not echo suppressed cells or restricted-list entries (tested; other input values may appear in messages); the designed ZK commitment keeps the event count *m* private (crypto evidence §5) | L | F. Arduh | T |
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
| T25 | Appeals | Appeal spam and round griefing: anyone can pre-file a guessable document hash, consuming round 1; a rejected hash can be re-filed indefinitely; no filer is recorded and open appeals never time out | Gas cost for direct filings; relayer rate limits. Planned: a salt in the appeal document (format 3), rounds not treated as an escalation count (VPR-069) | M | Operator, M. Nivoli | — |
| T26 | L2 | Sequencer censors governance or appeal transactions | Forced inclusion through L1 (runbook, Planned); filtering unaffected | M | M. Nivoli | — |
| T27 | L2 | Reorganisation before finality | Dashboard shows finality state; actions wait for finality (Planned) | L | Operator | — |
| T28 | L2 | RPC provider returns a false view | Several RPC providers; verifiers compare (Planned) | M | Operator | — |
| T29 | L2 | Gas price spike blocks anchoring or appeals | Small, constant transaction count; funded relayer; delayed anchoring tolerated | L | Operator | — |
| T30 | Data availability | Policy document or dataset unavailable | Mirrors on independent hosts; unavailability is visible | M | Operator | G |
| T31 | Restricted list | Declared but not enforced, stale, or wrong | Compile-time hash check (implemented); confidential auditor verification (Planned) | M | Auditor | T, A |
| T32 | Restricted list | Disclosure via the zone file or repository | The compiled zone contains restricted entries in clear, and they are identifiable because they carry no source label; the zone is therefore an operator-confidential file (written 0600, never published). Membership can also be probed through the live resolver; only attribution is withheld. Restricted entries are unlabelled in compiled zones and list contents are never committed to the repository; only an unsalted hash commitment is published | L against accidental labels; candidate-list testing remains possible | — | T |
| T33 | Metrics | Re-identification by joining releases with public data | See the [privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md); release policy for small schools | M | D. Truyol | — |
| T34 | Policy | Over-blocking of education, health, LGBTQ+, political or journalistic content | Reasons per entry; exceptions; charter never-block list; reviewer checks exceptions are reachable; appeals; expiry | M | Governor, reviewer | R, G |
| T35 | Tooling | Policy compiled without promised protection (missing feed) | Compiler fails closed | L | M. Bruno | T |
| T36 | CI and release | Compromised CI or maintainer account pushes malicious code | Branch rulesets (no force push, required CI); two approvals for contracts; signed-off commits; tagged releases | M | F. Boiero | G |
| T37 | Dependencies | Malicious or vulnerable package | Lockfile; Dependabot; review of updates | M | F. Schillage | G |
| T38 | Compiler | An exception cancels a restricted entry (fail-open on a legally mandated block) | `compile_rpz` refuses an exception equal to or covering a restricted entry, without naming it (tested) | L | M. Bruno | T |
| T39 | Anchor | Publisher anchors roots for future or long-past days (burning days, back-filling after the data are known) | None on-chain; verifiers compare `committedAt` with `day`. Planned: bound `day` to the current date window (VPR-066) | M | M. Nivoli | — |
| T40 | Anchor | A wrong root is permanent and the publisher cannot be revoked (only replaced); after a governor rotation the old publisher stays authorised until the new governor acts | Planned: explicit revocation and a governor-gated correction record (VPR-066) | M | M. Nivoli | — |
| T41 | Registry | Single-step `setGovernor` to a wrong address bricks a scope; `maxValidity` is uncapped and immutable, so a huge value makes expiry meaningless | Planned: two-step transfer and a protocol cap on validity (VPR-067); until then, scope creation parameters are reviewed at Gate A | M | M. Nivoli | — |
| T42 | Registry | Front-running of `createScope` for a canonical scope id | Manifest pins the expected governor (VPR-049). Planned: derive the scope id from the governor and name on-chain (VPR-068) | M | M. Nivoli | — |
| T43 | Contracts | Unbounded free text in `uri` and `datasetUri` written permanently | Planned: length cap and scheme allow-list (VPR-066) | L | M. Nivoli | — |
| T44 | Metrics | A release with counts below *k* still has a valid root | `vpr verify-root --k` and `validate_release(k)` detect it (tested); not enforced on-chain | M | F. Arduh | T |
| T45 | Roles | Issuer roles are per address and governor-controlled: one entity can use two addresses, the governor can assign itself a role, and checks read current roles, not roles at attestation time | Verifiers must replay `IssuerSet` events as of the attestation; EAS resolver planned (VPR-012) | M | M. Nivoli | — |
| T46 | Sync daemon | Untrusted policy `uri` (SSRF, oversized or hostile YAML) | Planned: fetch allow-list, size limit, safe loader with duplicate-key rejection (the loader part is implemented) | M | F. Schillage | — |
| T47 | Operations | A skipped day is indistinguishable from a day with no publishable cells; governor, issuer and publisher changes take effect instantly | Planned: daily "release or empty" marker and notice periods (VPR-066, governance) | L | Operator | — |
| T48 | Governance | Policy lapses permanently through governor inactivity or key loss | Charter fallback (protective categories only) applies; documented recovery | M | Signers | G |

## 5. Recourse beyond the governor

A colluding majority can reject an appeal. The design makes this visible: the rejection reasons are hashed on-chain and published. What it cannot provide is a remedy. The scope charter therefore names an external recourse path, such as a national ombudsperson, a data-protection authority or a child-rights body depending on the country, and commits to publishing the outcome. Choosing that path is a decision for the deploying partners ([open questions](../giga/OPEN_QUESTIONS_FOR_GIGA.md)).

## 6. Non-goals and accepted risks

- Filtering against users who deliberately use VPNs or their own devices' DNS (T06).
- Proving on-chain that the resolver behaved correctly at runtime (T03, T10).
- Protection against a compromise of the cryptographic primitives or of the L2 itself.
- Any form of per-user monitoring: the system is designed so that it cannot provide it.
