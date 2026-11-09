# Do no harm by design

*CC BY 4.0 · Supports indicator 9 of the [DPG Standard](https://digitalpublicgoods.net/standard/)*

A content filter for children can harm the people it is meant to protect. It can expose their browsing, block what they need to learn, or be turned into a censorship tool. This page lists the harms we anticipate and what the design does about each one. It is reviewed at every milestone and whenever a new deployment context is added.

## Harms we anticipate

| # | Harm | Who is affected | Design response | Where |
| --- | --- | --- | --- | --- |
| H1 | Children's browsing is recorded or exposed | Students, teachers | No query logs; the exporter emits only `(school_id, day, category)`; small-cell suppression with k = 10; no personal data on-chain | [PRIVACY_STATEMENT](PRIVACY_STATEMENT.md), [ADR-0007](adr/0007-k-anonymous-metrics-merkle.md), [INTERFACES I5](INTERFACES.md#i5--block-events-resolver-exporter--aggregator) |
| H2 | Over-blocking of educational or health content | Students, teachers | Exceptions with reasons; mandatory expiry; public appeals; the reviewer tests that exceptions are reachable | [ADR-0004](adr/0004-multisig-governor-expiry-appeals.md), `VPR.IndependentTest.v1` |
| H3 | The filter is repurposed for censorship | Students, the wider public | Policies published in full with reasons; multisig governor with an independent signer; scope limited to bounded networks; no national or ISP features | [ADR-0006](adr/0006-scope-school-networks-only.md), [GOVERNANCE](GOVERNANCE.md) |
| H4 | False sense of safety ("the school is protected" when it is not) | Schools, parents, donors | Protection claimed only with a valid independent test attestation; attestations expire; limitations stated openly | [ADR-0005](adr/0005-issuer-separation.md), [WHITEPAPER §10](WHITEPAPER.md#10-limitations) |
| H5 | Disclosure of illegal-content lists | Victims of abuse, the public | Restricted lists by hash only, never in the repository or in labelled zones | [ADR-0008](adr/0008-restricted-lists-hash-only.md) |
| H6 | Re-identification through appeals | Whoever files an appeal | Appeal document limited to scope, domain, request and reason; no personal fields; relayer so nobody needs a wallet | [INTERFACES I9](INTERFACES.md#i9--appeal-document-planned-vpr-017) |
| H7 | Key compromise lets an attacker change a policy | Everyone in the scope | 2-of-3 Safe; hardware wallets or passkeys; rotation with `setGovernor`; every change public and expiring | [GOVERNANCE rules](GOVERNANCE.md#rules) |
| H8 | Contract bugs lock or corrupt the record | Everyone in the scope | Minimal contracts, tests, static analysis, external audit before mainnet | [SECURITY.md](../SECURITY.md), [ROADMAP M3](ROADMAP.md) |

## 9a · Data privacy and security

The software does not collect, store or distribute personally identifiable information. Privacy is enforced by what is collected, not by what is deleted later:

- the resolver answers queries in memory and does not log them;
- the only data that leaves the resolver is a count per school, day and category;
- published datasets suppress any cell with fewer than ten events;
- on-chain data is institutional only: scope ids, public school ids, hashes, signatures and aggregate roots.

Each deployment publishes a Recursive operator Privacy Statement (RFC 8932) and commits to its hash in the deployment attestation. A data protection impact assessment, aligned with the UNICEF Policy on Personal Data Protection and the law of the pilot country, is carried out before any school is connected ([ROADMAP M1](ROADMAP.md)). Security vulnerabilities are handled under [SECURITY.md](../SECURITY.md).

## 9b · Inappropriate and illegal content

The project does not host or distribute user content. It does handle the *identification* of harmful content, which comes with its own rules:

- **Child sexual abuse material.** The project relies on established lists maintained by specialised organisations (such as the IWF URL List), which operators obtain directly from the provider under the provider's terms. These lists are never committed to this repository, never published and never labelled in compiled zones; only a hash commitment is public.
- **Reporting.** Anyone who finds illegal content through a deployment should report it to the national hotline (members of [INHOPE](https://www.inhope.org/)) or to the IWF. The block page will link to the relevant hotline for each country.
- **This repository.** Issues, pull requests or examples must never contain illegal content or links to it. Maintainers delete such material immediately, report it to the platform and the relevant hotline, and block the account involved.
- **Appeals and policy documents.** Both are public. The appeal relayer rejects submissions that contain anything other than a domain and a short reason, and the governor may decline to publish a domain name in a policy document when doing so would itself point people to abusive material; in that case the entry goes to the restricted list.

## 9c · Protection from harassment and safety of underage users

- Contributors interact on GitHub under the [Code of Conduct](../CODE_OF_CONDUCT.md). Reports go to the maintainers privately and are answered promptly; reports involving a minor take priority.
- Children are end users of the school network but **do not interact with the project directly**: there are no accounts, profiles, messaging or user-generated content. The appeal form is meant for teachers and school staff, and asks for no personal data.
- Maintainers do not request or accept personal information about students in any channel. Any such data posted by mistake is removed and the author is told why.

## Authorised representative

The DPG application for indicators 7 to 9 is submitted by Fernando Boiero, CTO, Xcapit (CryptoLab S.A.S.), dpg@xcapit.com.
