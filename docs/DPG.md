# Digital Public Good readiness

*CC BY 4.0 · Project self-assessment, not a DPGA decision. The VPR is not a registered Digital Public Good.*

The authoritative, indicator-by-indicator assessment, with evidence, gaps, owners and milestones, is in **[DPG_EVIDENCE_MATRIX.md](DPG_EVIDENCE_MATRIX.md)**. It records the DPG Standard version checked, including the v1.1.7 changes listed in the DPGA changelog. This page keeps the supporting material that the matrix cites. The application is planned for milestone M3 of phase 1, once the evidence for indicators 7 and 9 is signed ([ROADMAP](ROADMAP.md), VPR-025 in [BACKLOG](BACKLOG.md)).

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
