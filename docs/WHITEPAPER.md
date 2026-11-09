# Verifiable Policy Registry: accountable, privacy-preserving content filtering

*White paper · version 0.1 (draft) · November 2026 · Xcapit · CC BY 4.0*

## Abstract

Connecting schools to the internet exposes children to malware, phishing and harmful content, and filtering is the standard response. But filtering is also the most common instrument of censorship, and today's filters are opaque: the list of blocked sites, who changes it and whether children's browsing is logged all remain inside the operator. We present the Verifiable Policy Registry (VPR), a design and open-source implementation that turns a filtering policy into a public, multisig-governed, time-limited and contestable object on Ethereum, combined with independent attestations of each deployment and privacy-preserving impact metrics. Ethereum is used only for what it does well (a neutral, append-only record and a public attestation layer) while the limits of what a chain can prove are made explicit and covered by black-box testing and audit. The first deployment targets schools connected by UNICEF Giga.

## 1. Problem

Giga, the UNICEF–ITU initiative, has mapped more than 2.1 million schools and works to connect them all. Each newly connected school faces three risks:

1. **Technical threats:** malware, phishing and command-and-control traffic on shared, unmanaged devices.
2. **Harmful content:** child sexual abuse material, violent or adult content.
3. **Governance risk:** an opaque filter can block educational content or be repurposed for censorship, and neither UNICEF nor donors can verify it.

Commercial filters partly address the first two. None addresses the third: if the operator also keeps the change log, the log proves nothing.

## 2. Goals and non-goals

**Goals**

- G1. Anyone can see which policy is in force for a scope, what it blocks and why.
- G2. No single party (government, UNICEF, operator) can change a policy alone.
- G3. Every block is temporary by default and contestable.
- G4. Anyone can verify that a given school is protected, based on tests the operator does not control.
- G5. Impact can be reported to donors with figures that cannot be altered later, without exposing any child.
- G6. Everything is open source and reusable outside the pilot.

**Non-goals**

- Proving on-chain that a resolver behaves correctly at runtime (see §6).
- National or ISP-wide filtering. The design targets bounded networks with an accountable governor.
- Page-level (URL) filtering. DNS works at domain level; URL-level entries need another layer.

## 3. System model

**Actors.** *Governor*: a Safe multisig per scope (for example UNICEF Giga, the Ministry of Education and an independent reviewer, 2-of-3). *Operator*: runs the resolver and publishes metrics (Xcapit during the pilot). *Independent reviewer*: a child-protection NGO or university that tests deployments and handles appeals. *Auditor*: assesses conformance to standards. *Schools*: change one network setting and report wrongly blocked sites. *Public*: donors, journalists and researchers who verify.

**Scope.** A named policy context, for example `giga:AR:primary`, identified on-chain by `keccak256(scope)`.

**Components.** (1) `VerifiablePolicyRegistry` contract; (2) EAS attestations with three schemas and separate issuer roles; (3) `MetricsAnchor` contract; (4) a filtering DNS resolver driven by the published policy (RPZ); (5) off-chain tooling to hash policies, compile zones, aggregate metrics and verify roots. Details in [ARCHITECTURE.md](ARCHITECTURE.md).

## 4. Policy lifecycle

1. The policy document (YAML) lists selected categories, third-party feeds by provider and version, local blocks and exceptions, each with a reason. Its canonical JSON form is hashed with keccak256 into `contentHash`.
2. The document is published (for example on IPFS or a public repository). Restricted lists that cannot legally be published are committed to by `restrictedListHash` only.
3. The governor Safe calls `publishPolicy(scopeId, contentHash, restrictedListHash, uri, reasonCode, validity, resolvesAppeal)`. Validity is mandatory and bounded by the scope's `maxValidity` (for example 90 days).
4. The operator compiles the document into an RPZ zone and loads it into the resolver. The zone's header carries the content hash, so a reviewer can link a running configuration to an on-chain version.
5. If a version expires without renewal, `currentPolicy` reports it as not in force. The operational fallback (keep last policy, or protective-only categories) is a governance decision recorded in the scope's charter.

**Appeals.** A block page links to an appeal form. An appeal is filed on-chain with a public description (domain and reason, never personal data). The governor either publishes a new version that resolves it (`resolvesAppeal`) or rejects it, and both outcomes are public.

## 5. Privacy design

- **On-chain:** only institutional data (scope ids, public Giga school ids, hashes, signatures, aggregate roots).
- **Resolver:** no query logging. Only a short operational buffer, as declared in the Recursive operator Privacy Statement (RFC 8932) published with the deployment ([PRIVACY_STATEMENT.md](PRIVACY_STATEMENT.md)).
- **Metrics:** the exporter emits only `(school_id, day, category)` events. Cells with fewer than *k* events (default 10) are suppressed. The published dataset is committed by a Merkle root anchored daily; anyone can recompute it from the CSV.
- **Data protection:** the UNICEF Policy on Personal Data Protection and the pilot country's data law apply; a DPIA precedes the pilot.

Residual risk: small schools with low counts per category may see most cells suppressed. That is the intended trade-off: impact reporting degrades before privacy does.

## 6. What the chain proves, and what it does not

| Claim | Evidence | Trust assumption |
| --- | --- | --- |
| Policy vN is in force for scope S, signed by the governor | Registry state and events | Ethereum consensus; Safe signers |
| School X is protected under vN | Deployment attestation (operator) + independent test attestation (reviewer) | The reviewer tests honestly; tests are repeated before `validUntil` |
| Impact figures for day D were not changed | MetricsAnchor root + public dataset | None beyond hashing, once published |
| The resolver keeps no logs | RFC 8932 statement, published configuration, audit | Auditor and operator honesty |

A research track (roadmap M4) studies zero-knowledge proofs that published aggregates derive from the policy in force, which would narrow the last two rows.

## 7. Threat model (summary)

| Threat | Mitigation |
| --- | --- |
| Silent policy change by one party | Multisig governor; every change is a public, signed version |
| Permanent over-blocking | Mandatory expiry; appeals; independent signer |
| Operator certifies itself | Separate issuer roles; reviewer-issued test attestations |
| Re-identification from metrics | k-suppression; no identifiers collected |
| Disclosure of restricted lists | Hash-only commitment; restricted entries unlabelled in zones |
| Filter bypass (external DoH, VPN, alternative DNS) | Resolver blocks known public resolvers; reviewer tests bypasses each cycle |
| Signer key loss or compromise | Safe with hardware wallets or passkeys; `setGovernor` rotation; documented recovery |
| Contract bugs | Minimal contracts; tests; external audit and MIESC analysis before mainnet |

## 8. Standards

Included because each adds something verifiable:

| Framework | Role |
| --- | --- |
| ISO/IEC 27001 | Xcapit is certified as a software factory; the project is developed and operated under that ISMS |
| UNICEF Policy on Personal Data Protection + national law | Binding rules for UNICEF and its suppliers; DPIA |
| NIST SP 800-81r3 (2026) | Current reference for secure and protective DNS (RPZ, encrypted DNS, DNSSEC); resolver compliance matrix |
| RFC 8932 (BCP 232) | Recursive operator Privacy Statement; its hash is published on-chain |
| UK Safer Internet Centre school-filtering criteria + IWF list | The only framework specific to school filtering; published self-certification checklist |
| ITU Child Online Protection guidelines | Content categories used by Giga's parent organisations |
| EAS, W3C Verifiable Credentials 2.0 | Attestations verifiable on and off Ethereum |

Left out: UK DfE standards (they bind UK schools, not providers); CISA Protective DNS and DNS4EU (services, not certifications); ISO/IEC 27701 and 29100 (covered by the UNICEF policy and DPIA); GDPR and COPPA (not applicable to a Latin American pilot).

## 9. Deployment and cost

Proposed network: OP Mainnet, where EAS is deployed (alternative: Base). Expected load: about one transaction per day per scope for metrics, one per policy change, and one per school per test cycle. Institutional signers use hardware wallets or passkey-based smart accounts; nobody at schools handles crypto.

## 10. Evaluation plan

Pilot indicators (to be agreed with Giga): schools with a valid independent test attestation (target 20–50); 100% of policy changes published with signatures; zero personal data on-chain (audit); wrongly-blocked reports answered within 5 working days; resolver availability 99.9%; DPG registration approved; at least one party outside the project recomputes a published root.

## 11. Limitations

DNS filtering is coarse (domain level) and can be bypassed by devices that ignore network DNS; it complements, not replaces, education and device management. Governance quality depends on the independence of the reviewer. Expiry by default requires an operational process to renew policies on time.

## 12. References

- NIST SP 800-81 Rev. 3, *Secure Domain Name System (DNS) Deployment Guide*, March 2026.
- RFC 8932 / BCP 232, *Recommendations for DNS Privacy Service Operators*, 2020.
- RFC 8484 (DoH), RFC 7858 (DoT), RFC 4033–4035 (DNSSEC).
- UNICEF, *Policy on Personal Data Protection*, 2020.
- ITU, *Guidelines on Child Online Protection*, 2020.
- Ethereum Attestation Service, https://attest.org
- Digital Public Goods Alliance, *DPG Standard*.
- Giga and Government of Rwanda, *Crypto connectivity pilot* (Ethereum Foundation seed funding).
