# Do no harm by design

*CC BY 4.0 · Supports indicator 9 of the [DPG Standard](https://digitalpublicgoods.net/standard/)*

A content filter for children can harm the people it is meant to protect. It can expose their browsing, block what they need to learn, or be turned into a censorship tool. This page lists the harms we anticipate and what the design does about each one. It is reviewed at every milestone and whenever a new deployment context is added.

## Harms we anticipate

The full threat register, with owners and verification methods, is in [security/THREAT_MODEL.md](security/THREAT_MODEL.md); privacy risks from published metrics are analysed in [privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md](privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md); recourse and emergency procedures are in [GOVERNANCE.md](GOVERNANCE.md#escalation-and-external-recourse).

| # | Harm | Who is affected | Design response | Where |
| --- | --- | --- | --- | --- |
| H1 | Children's browsing is recorded or exposed | Students, teachers | Designed no-logging resolver and three-field exporter boundary; implemented input validation and small-cell suppression; no end-user personal data fields in the implemented contracts. Resolver/exporter validation remains Planned | [PRIVACY_STATEMENT](PRIVACY_STATEMENT.md), [ADR-0007](adr/0007-suppressed-metrics-merkle.md), [INTERFACES I5](INTERFACES.md#i5--block-events-resolver-exporter--aggregator) |
| H2 | Over-blocking of educational or health content | Students, teachers | Exceptions with reasons; mandatory contractual expiry; public appeal hashes and status; Planned reviewer tests of exceptions | [ADR-0004](adr/0004-multisig-governor-expiry-appeals.md), `VPR.IndependentTest.v1` |
| H3 | The filter is repurposed for censorship | Students, the wider public | Policies published in full with reasons (implemented); a multisig governor with an independent signer (designed: depends on the Safe configured at deployment); scope limited to bounded networks (project policy, ADR-0006, not enforced in code) | [ADR-0006](adr/0006-scope-school-networks-only.md), [GOVERNANCE](GOVERNANCE.md) |
| H4 | False sense of safety ("the school is protected" when it is not) | Schools, parents, donors | Proposed reporting rule requires a valid independent test attestation; schema enforcement, tests, expiry and revocation are Planned | [ADR-0005](adr/0005-issuer-separation.md), [WHITEPAPER §10](WHITEPAPER.md#10-limitations) |
| H5 | Disclosure of illegal-content lists | Victims of abuse, the public | Restricted lists by hash only, never in the repository or in labelled zones | [ADR-0008](adr/0008-restricted-lists-hash-only.md) |
| H6 | Re-identification or abuse through appeals | Whoever files an appeal; anyone named in one | Implemented contract stores only a document hash; Planned relayer limits fields and validates submissions; access and retention policy to be fixed in the DPIA | [INTERFACES I9](INTERFACES.md#i9--appeal-document-format-3-relayer-planned-vpr-017) |
| H7 | Key compromise lets an attacker change a policy | Everyone in the scope | 2-of-3 Safe (designed, deployment-dependent); hardware wallets or passkeys; two-step governor handover (threat model T41); every change public and expiring | [GOVERNANCE rules](GOVERNANCE.md#rules) |
| H8 | Contract bugs lock or corrupt the record | Everyone in the scope | Minimal contracts, tests, static analysis, external audit before mainnet | [SECURITY.md](../SECURITY.md), [ROADMAP M3](ROADMAP.md) |

## 9a · Data privacy and security

The proposed resolver necessarily processes personal data transiently: it would see client IP addresses and queried names in memory to answer each query. The design prohibits retaining, exporting or publishing that data, but this has not been validated against a running resolver or exporter:

- the reference resolver configuration disables query logging;
- the Planned exporter interface permits only school, day and category;
- the implemented aggregator suppresses cells below a configurable threshold (the examples use ten);
- the implemented contracts contain institutional identifiers, addresses, hashes and aggregate roots, not end-user fields.

Before any school deployment, Gate A requires a completed Recursive operator Privacy Statement, a DPIA and a jurisdiction-specific legal review. Publishing the statement hash in a deployment attestation is Planned; no such attestation exists. Applicable institutional policies depend on the partners that are actually confirmed ([ROADMAP M1](ROADMAP.md)). Security vulnerabilities are handled under [SECURITY.md](../SECURITY.md).

## 9b · Inappropriate and illegal content

The project does not host or distribute user content. It does handle the *identification* of harmful content, which comes with its own rules:

- **Child sexual abuse material.** The project relies on established lists maintained by specialised organisations (such as the IWF URL List), which operators obtain directly from the provider under the provider's terms. These lists are never committed to this repository, never published and never labelled in compiled zones; only a hash commitment is public.
- **Reporting.** Anyone who finds illegal content through a deployment should report it to the national hotline (members of [INHOPE](https://www.inhope.org/)) or to the IWF. The block page will link to the relevant hotline for each country.
- **This repository.** Issues, pull requests or examples must never contain illegal content or links to it. Maintainers delete such material immediately, report it to the platform and the relevant hotline, and block the account involved.
- **Appeals and policy documents.** Policy documents are public except for restricted-list contents. Appeal hashes are public; access to the off-chain documents and decisions is a Gate A DPIA decision. The Planned relayer rejects submissions outside the narrow appeal schema, and a domain that would itself direct people to abusive material belongs in the restricted list rather than a public policy entry.

## 9c · Protection from harassment and safety of underage users

- Contributors interact on GitHub under the [Code of Conduct](../CODE_OF_CONDUCT.md). Reports go to the maintainers privately and are answered promptly; reports involving a minor take priority.
- Children are end users of the school network but **do not interact with the project directly**: there are no accounts, profiles, messaging or user-generated content. The appeal form is meant for teachers and school staff, and asks for no personal data.
- Maintainers do not request or accept personal information about students in any channel. Any such data posted by mistake is removed and the author is told why.

## Authorised representative

The DPG application for indicators 7 to 9 is submitted by Fernando Boiero, CTO, Xcapit (CryptoLab S.A.S.), dpg@xcapit.com.
