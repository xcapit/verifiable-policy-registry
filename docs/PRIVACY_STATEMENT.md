# Recursive operator Privacy Statement (draft)

*Structure follows RFC 8932 §6 (Recursive operator Privacy Statement). Draft for the pilot; to be finalised with the DPIA in M1. Its keccak256 hash is published on-chain with each deployment attestation.*

## 1. Policy

1. **Treatment of IP addresses.** The resolver necessarily processes client IP addresses and queried names in memory to answer each query; this is personal-data processing even though nothing is retained. Client IP addresses are used only to answer queries and to apply access control. They are not written to disk and not shared. The full data inventory, with retention, is in the [privacy and re-identification analysis](privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md).
2. **Data collection and sharing.** No queried names, client IPs or device identifiers are logged. For each blocked query, the resolver emits a single event `(school_id, day, category)`, where `school_id` is the public Giga school identifier derived from the network the query came from. No other data leaves the resolver.
3. **Exceptions.** A rolling in-memory operational buffer of up to [N] hours may exist for abuse and incident handling. It is never exported. [N to be fixed in the DPIA.]
4. **Associated entities.** None receive query data. Aggregated datasets are published openly, with every cell below the threshold suppressed (pilot default k = 10 events) and the number of suppressed cells not published. The threshold counts events, not people; the release policy for small schools and sensitive categories is fixed in the DPIA.
5. **Correlation of data.** Not performed.
6. **Result filtering.** Filtering follows the policy in force for the scope, published in full with reasons at the URI recorded in the Verifiable Policy Registry. Restricted lists (IWF) are applied and committed to by hash.
7. **Applicable law.** UNICEF Policy on Personal Data Protection; data-protection law of the pilot country.

## 2. Practice

1. **Deviations from policy.** Any deviation is published as a new statement version and re-attested.
2. **Client-facing capabilities.** DNSSEC validation; DNS over TLS (RFC 7858) and DNS over HTTPS (RFC 8484); QNAME minimisation.
3. **Upstream capabilities.** [To be specified: upstream resolution mode and encryption.]
4. **Support.** Wrongly blocked sites can be reported from the block page; reports are handled through the appeal process.
5. **Data processing.** Operator: Xcapit (CryptoLab S.A.S.), Argentina, ISO/IEC 27001-certified. Hosting region: [to be agreed].

## 3. Enforcement and accountability

Independent black-box tests by the reviewer (EAS `VPR.IndependentTest.v1`); external audit with `VPR.Conformance.v1` attestation referencing this statement; published configuration hash in each `VPR.Deployment.v1` attestation.
