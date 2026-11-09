# Digital Public Good readiness

*CC BY 4.0 · Checked against [DPG Standard](https://github.com/DPGAlliance/DPG-Standard/blob/main/standard.md) v1.1.4 · Last review: 2026-11-09*

We intend to submit the Verifiable Policy Registry to the [Digital Public Goods Alliance](https://digitalpublicgoods.net/) at milestone M2 ([ROADMAP](ROADMAP.md)). This page maps each indicator to the evidence in this repository, so reviewers and contributors can see what is done and what is missing. It is tracked as [VPR-025](BACKLOG.md).

| # | Indicator | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Relevance to the SDGs | Ready | [§1 below](#1-relevance-to-the-sdgs), [WHITEPAPER](WHITEPAPER.md) |
| 2 | Approved open licence | Ready | [LICENSE](../LICENSE) (AGPL-3.0-only, OSI-approved), [LICENSES/](../LICENSES), [NOTICE](../NOTICE), [ADR-0002](adr/0002-licensing.md) |
| 3 | Clear ownership | Ready | [NOTICE](../NOTICE), [GOVERNANCE.md](../GOVERNANCE.md#ownership) |
| 4 | Platform independence | Ready | [§4 below](#4-platform-independence) |
| 5 | Documentation | Ready for the PoC | [README](../README.md), [ARCHITECTURE](ARCHITECTURE.md), [INTERFACES](INTERFACES.md), [CONTRIBUTING](../CONTRIBUTING.md) |
| 6 | Mechanism for extracting data and content | Ready | [§6 below](#6-extracting-data-and-content) |
| 7 | Privacy and applicable laws | In progress (DPIA due in M1) | [PRIVACY_STATEMENT](PRIVACY_STATEMENT.md), [§7 below](#7-privacy-and-applicable-laws) |
| 8 | Standards and best practices | Ready | [WHITEPAPER §7](WHITEPAPER.md#7-standards-and-compliance), [§8 below](#8-standards-and-best-practices) |
| 9 | Do no harm by design | Ready for the PoC | [DO_NO_HARM](DO_NO_HARM.md), [CODE_OF_CONDUCT](../CODE_OF_CONDUCT.md), [SECURITY](../SECURITY.md) |

## 1. Relevance to the SDGs

| SDG target | How the project contributes |
| --- | --- |
| **4.a** Safe, non-violent, inclusive and effective learning environments | Connected schools get protection from malware, phishing and harmful content without turning the network into a surveillance tool |
| **16.2** End abuse, exploitation and all forms of violence against children | Blocks access to child sexual abuse material through established restricted lists, and reduces children's exposure to exploitation online |
| **16.6** Effective, accountable and transparent institutions | Every policy change is public, signed by several institutions, time-limited and contestable |
| **16.10** Public access to information and protection of fundamental freedoms | Mandatory expiry, published reasons and on-chain appeals limit over-blocking and make censorship visible |
| **9.c** Universal access to ICT | Removes a common barrier to connecting schools (fear of unsafe internet) in programmes such as Giga |

## 4. Platform independence

All mandatory dependencies are open source or open standards, and each has a functional alternative:

| Dependency | Licence / nature | Alternative without changes to the core |
| --- | --- | --- |
| Ethereum (OP Mainnet) | Open protocol, MIT-licensed clients | Any EVM chain where EAS is available (Base, Ethereum L1, others) |
| Ethereum Attestation Service | Open source (MIT) | W3C Verifiable Credentials 2.0 signed off-chain; the schemas are CC0 |
| Safe multisig | Open source (LGPL-3.0) | Any contract wallet or multisig that can call the registry: the governor is a plain address |
| Unbound | Open source (BSD) | PowerDNS Recursor, Knot Resolver or BIND: the zone is standard RPZ |
| Hardhat, Python, pycryptodome, PyYAML | Open source | Foundry; any keccak256 implementation |

No component requires a proprietary service, a paid API or a specific cloud provider.

## 6. Extracting data and content

All data the project produces is non-PII and published in open formats:

- policy documents: YAML or JSON, with a public JSON Schema ([`schemas/policy.schema.json`](../schemas/policy.schema.json));
- impact datasets: CSV and JSON ([`schemas/dataset.schema.json`](../schemas/dataset.schema.json)), verifiable with `vpr verify-root`;
- attestations: EAS records, readable through public EAS indexers or directly from the chain;
- registry and anchor state: public contract storage and events, readable with any Ethereum client;
- compiled filters: standard RPZ zone files.

## 7. Privacy and applicable laws

The project is designed not to process personal data at all (see [DO_NO_HARM §9a](DO_NO_HARM.md#9a--data-privacy-and-security)). Each deployment must comply with:

- the UNICEF Policy on Personal Data Protection, for deployments with UNICEF;
- the data-protection law of the country where the network runs (for the Latin American pilot, for example, Argentina's Law 25.326, Brazil's LGPD or the equivalent national law);
- a published RFC 8932 privacy statement for the resolver, whose hash is attested on-chain.

A DPIA is completed with the deploying partner before the pilot (milestone M1). Development and operation follow Xcapit's ISO/IEC 27001-certified information security management system.

## 8. Standards and best practices

- Open standards: RPZ, DNSSEC (RFC 4033–4035), DoT (RFC 7858), DoH (RFC 8484), RFC 8932, EAS, W3C VC 2.0, JSON Schema 2020-12, SPDX licence identifiers.
- Sector guidance: NIST SP 800-81r3, UK Safer Internet Centre filtering criteria, ITU Child Online Protection guidelines.
- Development practice: [Principles for Digital Development](https://digitalprinciples.org/) (open standards, privacy by design, reuse), Conventional Commits, DCO sign-off, continuous integration, ADRs, semantic versioning.

## Still to do before submission

- [ ] Complete the DPIA and resolve the placeholders in the privacy statement (VPR-004, VPR-005).
- [ ] Publish the threat model (VPR-003).
- [ ] Deploy to OP Sepolia and add contract addresses to the README (VPR-010).
- [ ] Add the country hotline link to the block page (VPR-017).
- [ ] Confirm the authorised representative details in the DPGA application form.
