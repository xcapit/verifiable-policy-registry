# Recursive operator Privacy Statement (draft)

*Structure follows RFC 8932 §6 (Recursive operator Privacy Statement). **Designed, not an account of current operations.** This draft must be completed through the DPIA in M1. No deployment attestation exists; committing the final statement hash in each deployment attestation is Planned.*

## 1. Policy

1. **Treatment of IP addresses.** A resolver necessarily processes client IP addresses and queried names in memory to answer each query; this is personal-data processing even without retention. The proposed policy permits their use only to answer queries and apply access control, and prohibits writing or sharing them. This behaviour has not been validated against a running resolver. The full designed data inventory is in the [privacy and re-identification analysis](privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md).
2. **Data collection and sharing.** The proposed resolver configuration disables query logging. The Planned exporter would emit one event `(school_id, day, category)` for each blocked query, where `school_id` is a public institutional identifier derived from the source network. The exporter is not implemented, so the claim that no other data leaves the resolver remains Designed.
3. **Exceptions.** A rolling in-memory operational buffer of up to [N] hours may exist for abuse and incident handling. It is never exported. [N to be fixed in the DPIA.]
4. **Associated entities.** None receive query data. Aggregated datasets are published openly, with every cell below the threshold suppressed (pilot default k = 10 events) and the number of suppressed cells not published. The threshold counts events, not people; the release policy for small schools and sensitive categories is fixed in the DPIA.
5. **Correlation of data.** Not performed.
6. **Result filtering.** A deployment would follow the policy in force for the scope, published in full with reasons at the URI recorded in the registry. Any restricted list would be handled under the provider's terms and represented by a hash commitment; declaration of that hash does not prove enforcement.
7. **Applicable law and institutional policy.** Unknown until a country and partners are confirmed. The Gate A legal review must identify applicable national and international law. The UNICEF Policy on Personal Data Protection is relevant only if the confirmed institutional arrangement makes it applicable; it is not presented here as law or as evidence of compliance.

## 2. Practice

1. **Deviations from policy.** Proposed procedure: publish a new statement version and obtain a new attestation. Not implemented.
2. **Client-facing capabilities.** The reference fragment configures DNSSEC validation, DNS over TLS and QNAME minimisation. DNS over HTTPS is commented out and depends on the Unbound build. None has been exercised in this repository.
3. **Upstream capabilities.** [To be specified: upstream resolution mode and encryption.]
4. **Support.** Planned: wrongly blocked sites can be reported from a block page and handled through the appeal process (VPR-017).
5. **Data processing.** Proposed operator: Xcapit (CryptoLab S.A.S.), Argentina. No operator or hosting region has been agreed for a deployment.

## 3. Enforcement and accountability

Planned controls: independent black-box tests by the reviewer; a `VPR.IndependentTest.v1` attestation; external audit referenced by a `VPR.Conformance.v1` attestation; and a configuration hash in `VPR.Deployment.v1`. The schemas are Defined, not registered, and the role-enforcing schema resolver is Planned (VPR-012).
