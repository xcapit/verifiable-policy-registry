# Contract assurance

*CC BY 4.0 · Pre-audit evidence for `VerifiablePolicyRegistry`, `MetricsAnchor` and `IssuerRoleResolver`. This is not an audit. The contracts have not been audited by a third party and are not deployed on any public network. Every figure below is produced by CI on each push; the run cited is [42795525989](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42795525989).*

## 1. Summary

| Evidence | Result | Where it runs |
| --- | --- | --- |
| Unit and integration tests (Hardhat) | 50 passing, including the resolver exercised through the published EAS 1.9.0 contracts | CI job `contracts` |
| Static analysis (Slither 0.11.3, 100 detectors) | 0 findings; 5 accepted findings annotated in the source with their justification (§3) | CI job `static-analysis`, fails on any finding |
| Invariant tests (Foundry) | 11 invariants, each 512 runs × 128 calls (65 536 calls per invariant) | CI job `invariants` |
| Property fuzz tests (Foundry) | 6 properties, 5 000 runs each | CI job `invariants` |
| Mutation check | 11 of 11 injected bugs caught (§5) | CI job `invariants` |
| Coverage (solidity-coverage) | 100 % statements, lines and functions; 99.34 % branches (§7) | CI job `contracts`, artifact `contracts-reports` |
| Gas | Per-function table (§8, [benchmarks](../benchmarks/BENCHMARKS.md)) | CI job `contracts` |

## 2. Build

The three contracts are compiled with solc 0.8.24 (pragma pinned to `=0.8.24`), optimizer enabled with 200 runs, EVM version `cancun`, identically in [`hardhat.config.js`](../../contracts/hardhat.config.js) and [`foundry.toml`](../../contracts/foundry.toml). Cancun is supported on OP Stack chains since the Ecotone upgrade. Test-only dependencies are pinned: `forge-std` to the official repository at tag v1.16.2 (commit `bf647bd`, recorded in `package-lock.json`) and `@ethereum-attestation-service/eas-contracts` to 1.9.0. EAS is deployed in tests from its published artifacts, not recompiled.

None of the contracts holds funds or is upgradeable. `MetricsAnchor` makes one external call, a view to the registry; `IssuerRoleResolver` makes one view call per attestation to the registry; `VerifiablePolicyRegistry` makes none.

## 3. Static analysis

Slither runs on every push and fails the build on any finding at any severity, informational included. The findings below were reviewed and accepted; each is suppressed only at its location, with the reason written next to it.

| Detector | Location | Why it is accepted |
| --- | --- | --- |
| `locked-ether` | `IssuerRoleResolver` | The EAS resolver interface requires `attest`, `multiAttest`, `revoke` and `multiRevoke` to be `payable`. Each reverts with `NotPayable` when called with value, and `isPayable()` returns false, so EAS never forwards value. |
| `unused-return` | `MetricsAnchor._governor` | `maxValidity` from `registry.scopes` is not needed to authorise the governor. |
| `calls-loop` | `IssuerRoleResolver._check` | One view call per attestation to the trusted registry fixed at deployment; the batch size is chosen by the caller of EAS. |
| `timestamp` | `MetricsAnchor._checkPublishable` | Day-granularity comparisons are the intended behaviour; see §9 for OP Stack time. |
| `timestamp` | `VerifiablePolicyRegistry.currentPolicy` | Expiry is defined against block time; see §9. |

## 4. Properties under fuzzing

Each invariant restates a property of the [white paper](../WHITEPAPER.md#33-properties) (§3.3) or of [INTERFACES](../INTERFACES.md). Handlers call every state-changing function from random actors, authorised or not, with mostly valid and some invalid inputs, and keep a ghost model of what the contract must contain. A reachability test in each suite proves that the handlers reach every state the invariants talk about, so that an invariant cannot pass vacuously.

| Property | Invariant | Suite |
| --- | --- | --- |
| P2 · Versions are append-only and never modified | `invariant_versionsAppendOnly` | [`RegistryInvariants`](../../contracts/test-foundry/RegistryInvariants.t.sol) |
| P4 · Every version expires within the scope's maximum validity, itself at most 365 days | `invariant_boundedDuration` | idem |
| Reason codes in 1..6; code 3 exactly for versions that resolve an appeal | `invariant_reasonCodes` | idem |
| P5 · An appeal is accepted only by a version of its scope that names it; a rejection carries a reason; final states and resolutions never change | `invariant_appealResolution` | idem |
| Neither the governor nor the pending governor holds an issuer role | `invariant_governorHoldsNoRole` | idem |
| P3 (contract part) · Only the governor, or the pending governor accepting, changes governed state | `invariant_onlyGovernorMutates` | idem |
| The stored state of every day equals the model: written once by the publisher, then changed only by governor corrections that increment the revision | `invariant_daysMatchModel` | [`AnchorInvariants`](../../contracts/test-foundry/AnchorInvariants.t.sol) |
| A day is empty exactly when its root is 0, and was written only after it ended | `invariant_committedDaysWellFormed` | idem |
| The publisher writes only ended days, within the back-fill window in force, and never the same day twice | `invariant_anchoringWindow` | idem |
| No row verifies against an empty day | `invariant_emptyDaysNeverVerify` | idem |
| Only the publisher anchors; only the governor corrects and appoints | `invariant_onlyAuthorisedWrites` | idem |

Stateless properties in [`PropertyFuzz`](../../contracts/test-foundry/PropertyFuzz.t.sol): any row of any release of 1 to 40 rows verifies with its proof, and changing its count, unit, category or day breaks it; the length-prefixed leaf encoding is unambiguous; distinct (governor, name) pairs give distinct scope ids, and creating the same name from another address never touches the original scope; for any well-formed encoding of each schema the resolver reads exactly the scope id a decoder reads; any non-canonical string offset or truncated head is refused.

## 5. Mutation check

A test suite that never fails proves little. [`scripts/mutation_check.py`](../../contracts/scripts/mutation_check.py) injects one realistic bug at a time, runs the suite that should catch it with a deliberately shallow campaign (64 runs × 32 calls), and requires it to fail. CI runs it on every push.

| Id | Injected bug | Caught by |
| --- | --- | --- |
| A1 | The publisher may anchor the day that is still open | `AnchorInvariants` |
| A2 | The back-fill window is one day too wide | `AnchorInvariants` |
| A3 | Anyone may correct a root | `AnchorInvariants` |
| A4 | The publisher may rewrite an anchored day | `AnchorInvariants` |
| A5 | The internal-node tag is confused with the leaf tag | `PropertyFuzz` |
| R1 | Validity is bounded by the global cap instead of the scope's maximum | `RegistryInvariants` |
| R2 | Reason code 3 is no longer tied to resolving an appeal | `RegistryInvariants` |
| R3 | The pending governor may be given an issuer role | `RegistryInvariants` |
| R4 | Anyone may publish a policy version | `RegistryInvariants` |
| R5 | A resolved appeal may be rejected again | `RegistryInvariants` |
| E1 | A non-canonical attestation encoding is accepted | `PropertyFuzz` |

The first run left A4 and R5 alive. A4 survived because the anchor model followed a rewrite instead of flagging it; R5 because only the appeal status, not its resolution, was compared, and acceptances were rare. Both suites were strengthened before this table was produced. R3 also showed that a shallow campaign can miss a two-step sequence, so the handler now targets the pending governor half of the time.

## 6. Integration with EAS

[`EasIntegration.test.js`](../../contracts/test/EasIntegration.test.js) deploys `SchemaRegistry` and `EAS` 1.9.0, registers the three VPR schemas with their resolvers and goes through `EAS.attest`, `multiAttest` and `revoke`: issuance only by the holder of the schema's role in the scope, refusal across scopes and after a role is withdrawn, revocation only by the attester, batches failing as a whole, malformed data and value refused. Attestation UIDs are read from the `Attested` event, since they depend on the block timestamp. [`scripts/check-eas.js`](../../contracts/scripts/check-eas.js) checks a deployment manifest against the chain: each schema UID is registered with the schema string and revocability of [`schemas/eas-schemas.json`](../../schemas/eas-schemas.json), and its resolver is the manifest's, has the matching `SchemaKind`, points to the manifest's registry and EAS, and is not payable. On OP Stack chains EAS and SchemaRegistry are predeploys at `0x4200000000000000000000000000000000000021` and `0x4200000000000000000000000000000000000020`.

## 7. Coverage

| Contract | Statements | Branches | Functions | Lines |
| --- | --- | --- | --- | --- |
| `IssuerRoleResolver` | 100 % | 100 % | 100 % | 100 % |
| `MetricsAnchor` | 100 % | 100 % | 100 % | 100 % |
| `VerifiablePolicyRegistry` | 100 % | 98.68 % | 100 % | 100 % |

The one branch not covered is the role check in `acceptGovernor`. It is unreachable while `proposeGovernor` and `setIssuer` enforce the same rule, and is kept as defence in depth (marked in the source). Mutant R3 shows that removing the reachable guard is caught.

## 8. Gas

Measured by `hardhat-gas-reporter` over the unit tests (solc 0.8.24, 200 runs, `cancun`). Minimum and maximum include short and maximum-length (256-byte) URIs.

| Function | Min | Max | Average |
| --- | --- | --- | --- |
| `createScope` | 71 259 | 163 017 | 73 097 |
| `setIssuer` | 27 322 | 51 449 | 49 584 |
| `proposeGovernor` | 28 986 | 51 126 | 46 198 |
| `acceptGovernor` | — | — | 31 922 |
| `publishPolicy` | 125 180 | 308 489 | 152 795 |
| `fileAppeal` | 104 289 | 118 898 | 114 724 |
| `rejectAppeal` | — | — | 55 847 |
| `setPublisher` | 32 553 | 75 179 | 64 548 |
| `commitRoot` | 98 484 | 281 768 | 116 835 |
| `markEmpty` | — | — | 55 999 |
| `correctRoot` | 39 609 | 84 305 | 61 686 |
| Deployment: registry / anchor / resolver | | | 1 679 541 / 1 148 815 / 687 077 |

These are L2 execution gas figures. On OP Stack a transaction also pays an L1 data fee that depends on the compressed calldata size and the L1 blob or calldata price; it is not included. The recurring cost per scope and day is one `commitRoot` (or `markEmpty`).

## 9. Time and ordering on OP Stack

Two functions depend on block time: `MetricsAnchor` derives the UTC day from it, and `currentPolicy` compares it with expiry. On OP Stack the L2 block timestamp is not chosen by the sequencer. The derivation rules set it to the previous block's timestamp plus the block time, and bound it to its L1 origin: `l1_origin.timestamp ≤ block.timestamp ≤ max(l1_origin.timestamp + max_sequencer_drift, prev_l2_timestamp + l2_block_time)`, with `max_sequencer_drift` = 1800 s since the Fjord upgrade ([derivation specification](https://specs.optimism.io/protocol/derivation.html); [Fjord](https://specs.optimism.io/protocol/fjord/derivation.html)). The day number therefore follows wall-clock UTC.

What a sequencer can do is order and delay transactions. Consequences and mitigations:

- **A delayed `commitRoot` can cross a day boundary.** With a back-fill window of one day, a root submitted shortly before the window closes could be refused with `DayTooOld`. Publishers should anchor early in the window; we recommend a window of at least two days for operational scopes.
- **Expiry.** A renewal submitted close to expiry can be included after it, leaving a short gap in which `currentPolicy` reports the policy as not in force and the charter fallback applies. Renewal is a signed act before expiry (reason code 2, [GOVERNANCE](../GOVERNANCE.md)); a charter should schedule it days, not hours, ahead.
- **Censorship.** A sequencer that refuses governance or appeal transactions can be bypassed by depositing them through L1 (`OptimismPortal`); the derivation rules force their inclusion, at the latest when the sequencing window (typically 12 hours) has elapsed. Filtering itself does not depend on the chain's liveness.
- **Finality.** An L2 block is final only when the batch that contains it is derived from finalized L1 blocks. Verifiers and the dashboard should read state at the `finalized` (or at least `safe`) head, and the deployment manifest states the confirmation policy (`confirmations`).
- **Front-running.** Scope creation cannot be pre-empted, because the scope id binds the creator. An appeal hash seen in the mempool can be filed first by someone else, which only creates the same appeal (the filer is not recorded by design).

## 10. Not covered, and next steps

- No third-party audit (milestone M3, VPR-024). This document is input to it, not a substitute.
- No formal verification. Candidates for symbolic checking (Halmos or Certora) are the reason-code rule, the appeal state machine and the anchoring window, which are small and fully specified.
- Event emission is tested in the unit tests, not in the invariant suites; indexers should rely on the events listed in [INTERFACES](../INTERFACES.md) and on reading state.
- The Merkle encoding is checked against the Python implementation through shared test vectors and against a Solidity reference model by fuzzing; there is no cross-language differential fuzzing yet.
- Gas costs of the planned ZK verifier are not known; they will be measured in M4.

## 11. Reproduce

```bash
cd contracts
npm ci
npx hardhat test                                   # unit and EAS integration tests
REPORT_GAS=1 npx hardhat test                      # gas table
npx hardhat coverage                               # coverage
FOUNDRY_PROFILE=ci forge test                      # fuzz and invariant tests (Foundry 1.3.5)
python3 scripts/mutation_check.py                  # mutation check
slither . --compile-force-framework hardhat --filter-paths "node_modules|test-foundry"   # Slither 0.11.3
```
