# Contract assurance

*CC BY 4.0 · Pre-audit evidence for `VerifiablePolicyRegistry`, `MetricsAnchor` and `IssuerRoleResolver`. This is not an audit. The contracts have not been audited by a third party and are not deployed on any public network. Figures marked CI are produced on every push; the run cited is given with each figure.*

## 1. Summary

| Evidence | Result | Where it runs |
| --- | --- | --- |
| Unit and integration tests (Hardhat) | 53 passing, including the resolver exercised through the published EAS contracts v1.4.0 | CI job `contracts` |
| Static analysis (Slither 0.11.3, 100 detectors) | 0 findings; 5 accepted findings annotated in the source with their justification (§3) | CI job `static-analysis`, fails on any finding |
| Invariant tests with a specification oracle (Foundry) | 11 invariants, 512 runs × 128 calls each in CI | CI job `invariants` |
| Bounded symbolic checks (Halmos 0.3.3) | 16 checks pass for all inputs within stated bounds, one transaction from a fixed state, with no timeout and no cut path; 2 canaries fail as they must; 22 of 22 applicable mutants caught (§4.1) | CI job `symbolic`; mutant run local |
| Property fuzz tests (Foundry) | 10 tests: 8 fuzzed properties (5 000 runs each in CI), the shared vector and event attribution | CI job `invariants` |
| Targeted mutation check | 26 of 26 mutants caught under three fixed seeds, 15 of them proposed by a separate internal review (§5.1) | CI job `invariants` |
| Mutation score over the whole test stack (slither-mutate) | 784 mutants: 715 killed (91.2 %); the 69 survivors are equivalent or unreachable, so every behaviour-changing mutant is killed (§5.2) | Measured locally, reproducible |
| Coverage (solidity-coverage) | 100 % statements, lines and functions; 98.68 % to 100 % branches (§7) | CI job `contracts`, enforced as a gate |
| Gas | Per-function table (§8) | CI job `contracts` |

## 2. Build and dependencies

The three contracts are compiled with solc 0.8.24 (pragma pinned to `=0.8.24`), optimizer enabled with 200 runs, EVM version `cancun`, identically in [`hardhat.config.js`](../../contracts/hardhat.config.js) and [`foundry.toml`](../../contracts/foundry.toml). Cancun is supported on OP Stack chains since the Ecotone upgrade. Sources are ASCII-only, which CI checks. Test-only dependencies are pinned: `forge-std` to the official repository at tag v1.17.0 (commit `f3dae6e`, recorded in `package-lock.json`), and the npm package `@ethereum-attestation-service/eas-contracts` 1.9.0, whose `EAS` and `SchemaRegistry` report version 1.4.0; tests deploy them from the package's compiled artifacts and assert that version.

None of the three VPR contracts holds funds or is upgradeable. `MetricsAnchor` makes one external call, a view to the registry; `IssuerRoleResolver` makes one view call per attestation to the registry; `VerifiablePolicyRegistry` makes none. The resolver trusts the EAS contract it is constructed with. On OP Stack chains EAS and SchemaRegistry are predeploys at `0x4200000000000000000000000000000000000021` and `0x4200000000000000000000000000000000000020`, behind proxies that the chain's upgrade process can change; their deployed version can therefore differ from the version tested here, and [`scripts/check-eas.js`](../../contracts/scripts/check-eas.js) reports it.

## 3. Static analysis

Slither runs on every push and fails the build on any finding at any severity, informational included. The findings below were reviewed and accepted. Each is suppressed only for the function (or, for `locked-ether`, the contract) where it occurs, with the reason written next to it.

| Detector | Scope of the suppression | Why it is accepted |
| --- | --- | --- |
| `locked-ether` | contract `IssuerRoleResolver` (the detector reports at contract level) | The EAS resolver interface requires `attest`, `multiAttest`, `revoke` and `multiRevoke` to be `payable`. Each reverts with `NotPayable` when called with value, and `isPayable()` returns false, so EAS never forwards value. |
| `unused-return` | `MetricsAnchor._governor` | `maxValidity` from `registry.scopes` is not needed to authorise the governor. |
| `calls-loop` | `IssuerRoleResolver._check` | One view call per attestation to the trusted registry fixed at deployment; the batch size is chosen by the caller of EAS. |
| `timestamp` | `MetricsAnchor._checkPublishable` | Day-granularity comparisons are the intended behaviour; see §9. |
| `timestamp` | `VerifiablePolicyRegistry.currentPolicy` | Expiry is defined against block time; see §9. |

## 4. Properties under fuzzing

The Foundry handlers call the state-changing functions of each contract from random actors, authorised or not, with valid and invalid inputs biased towards boundaries (the last valid and first invalid day of the back-fill window, the expiry instant, URIs and names at and just above their limits, the scope's maximum validity, the 365-day cap). Every call is checked against an **oracle written from the specification** ([INTERFACES](../INTERFACES.md) I2 and I7, [white paper](../WHITEPAPER.md#33-properties) §3.3): if the specification accepts the call it must succeed, and if it refuses the call it must revert. The oracle reads contract state but never reuses the contract's decision logic, so it catches both an accepted invalid call and a refused valid one. Each suite has a reachability test showing that the handlers reach every state the invariants refer to.

Registry ([`RegistryInvariants`](../../contracts/test-foundry/RegistryInvariants.t.sol)): two initial scopes with different maximum validities, plus scopes created during the campaign; `createScope`, `publishPolicy`, `fileAppeal`, `rejectAppeal`, `setIssuer`, `proposeGovernor`, `acceptGovernor` and time jumps.

| Property | Invariant |
| --- | --- |
| Every call is accepted exactly when the specification accepts it (P3 for the contract, P4, reason codes, appeals and roles; no valid call is refused) | `invariant_oracleAgrees` |
| P2 · Versions are append-only and no stored field of a past version changes | `invariant_versionsImmutable` |
| P4 · Every scope's maximum validity is at most 365 days, and every version expires within it | `invariant_boundedDuration` |
| `currentPolicy` returns the latest version, in force exactly while `block.timestamp < expiresAt` | `invariant_currentPolicyInForce` |
| Reason codes are in 1..6; code 3 exactly for versions that resolve an appeal | `invariant_reasonCodes` |
| P5 · An appeal keeps its scope, is accepted by exactly one version of that scope and by none of another, a rejection carries a reason, and final states and resolutions never change; an open or accepted document cannot be filed again (oracle) | `invariant_appealResolution` |
| Neither the governor nor the pending governor of any scope holds an issuer role | `invariant_governorHoldsNoRole` |

Anchor ([`AnchorInvariants`](../../contracts/test-foundry/AnchorInvariants.t.sol)): `commitRoot`, `markEmpty`, `correctRoot`, `setPublisher`, governor rotation in the registry, and time jumps that often land on a UTC midnight.

| Property | Invariant |
| --- | --- |
| Only the publisher writes, once per day, only ended days within the window; only the current governor corrects and appoints; no valid call is refused | `invariant_oracleAgrees` |
| Each written day equals the model: root, emptiness, revision, dataset URI, and a commit time that corrections never change | `invariant_daysMatchModel` |
| A day is empty exactly when its root is 0, and was first written only after it ended | `invariant_committedDaysWellFormed` |
| `verifyRow` agrees with an independently computed leaf: a one-row release verifies exactly while its root is current and the day is not empty | `invariant_verifyRowMatchesModel` |

Stateless properties in [`PropertyFuzz`](../../contracts/test-foundry/PropertyFuzz.t.sol): the shared cross-language vector (leaf and root, as in the Python and Hardhat tests); any row of any release of 1 to 40 rows verifies with its proof, and changing its count, unit, category or day breaks it; the length-prefixed leaf encoding is unambiguous; distinct (governor, name) pairs give distinct scope ids, and creating the same name from another address never touches the original scope; for each schema the resolver accepts an attestation exactly when the attester holds the schema's role, never another; a batch is accepted exactly when every attestation in it is; the resolver reads the scope id a decoder reads and refuses non-canonical string offsets and truncated heads.

### 4.1 Bounded symbolic checks (Halmos)

The fuzz campaigns above sample inputs. The checks in [`test-foundry/symbolic/`](../../contracts/test-foundry/symbolic/) are explored symbolically by Halmos 0.3.3 with the Yices 2.6.4 solver, so they hold for **every** value of their parameters within the bounds below, not for the values a fuzzer happened to draw. Every address, hash, reason code, validity, day number and block timestamp is symbolic. Each UTC midnight, each window edge and the expiry instant are therefore covered, not sampled.

What each check states, and how far it goes:

- **One transaction from a fixed concrete state.** Each suite's `setUp` builds a small state: two or three scopes, a pending handover, an issuer, open, rejected and accepted appeals, and anchored and empty days. A check covers one call from that state. These are bounded results, not an induction over all reachable states; sequences of calls are covered by the invariant campaigns of §4 only.
- **Acceptance rules.** The function is called with a low-level call, and its success is compared with a predicate written from [INTERFACES](../INTERFACES.md) I2 and I7. The predicate reads state through public getters and never calls the contract's own checks. A plain call would not do, because Halmos treats a reverting path as passing: a contract that wrongly refused a valid call would go unnoticed. On success, the stored result is checked field by field.
- **Frame conditions.** One call with arbitrary calldata (any non-view function, any arguments) from an arbitrary sender. Afterwards, state the specification declares final must be unchanged.
- **Bounds.**
  - Strings have lengths 0, 256 and 257, the URI bound and one past it; scope names have lengths 0, 1, 128 and 129.
  - Loops are unrolled up to 16 times, and the run is rejected if any path was cut by that bound.
  - The solver runs without timeouts, so every branch is decided exactly, and a timeout counts as a failure, not a pass.
  - Block time is symbolic from the fixture time on, and is assumed to satisfy `block.timestamp + 365 days < 2^64` for the registry and `block.timestamp / 1 days < 2^32` for the anchor; both bounds lie more than eleven million years ahead.
- **Not vacuous.**
  - Each suite has a canary: a copy of a check whose predicate moves one boundary by one unit (validity `<` instead of `<=` the scope's maximum; the back-fill window one day narrower). The canary must produce a counterexample, and in each case the counterexample lies exactly on the moved boundary.
  - The mutants of §5.1 that fall within these suites are injected one at a time, and the named check must fail on each. All 22 are caught: A1 to A4, A6 to A11, and R1 to R12 (`symbolic_check.py --mutants` at commit 0144a6a, run locally on one laptop: about 11 minutes for the checks and 27 minutes in all). A5 (node hashing in `verifyRow`) and E1 to E3 (the resolver) are outside these suites. The first run let A9 survive (a correction that rewrites `committedAt`), because the correction check ran at the time of the original write; the check now runs at a symbolic later time.
- **Keccak256.** Mapping slots are keccak256 of their key, and Halmos models keccak256 as injective. Every check with a symbolic scope, appeal, day or address therefore relies on that model to keep distinct keys in distinct slots, which is the standard assumption that keccak256 has no collision.
- **Storage reads.** The frame checks read stored versions and commitments from raw storage slots, because Halmos cannot decode a stored string after a write to a symbolic slot. `setUp` checks the assumed layout against the public getters, so a layout change makes the suite fail rather than pass vacuously.

| Contract | Check | Statement |
| --- | --- | --- |
| Registry | `check_publishPolicy_acceptedExactlyWhenSpecified` | `publishPolicy` succeeds exactly when the caller governs an existing scope, the content hash is not 0, 0 < validity ≤ the scope's maximum, the URI is at most 256 bytes, the reason code is in 1..6, the code is 3 exactly when an appeal is resolved, and a resolved appeal is open and belongs to the scope. On success the new version holds exactly the arguments, `expiresAt = publishedAt + validity`, it is the current version and in force, the resolved appeal is accepted with the content hash, and no other open appeal changes. |
| Registry | `check_rejectAppeal_acceptedExactlyWhenSpecified` | Rejection succeeds exactly for an open appeal, by the governor of the appeal's scope, with a non-zero reason; the appeal keeps its scope. |
| Registry | `check_fileAppeal_acceptedExactlyWhenSpecified` | Filing succeeds exactly for an existing scope and a non-zero document whose latest round is absent or rejected, and opens round + 1 under `appealIdOf`. |
| Registry | `check_setIssuer_acceptedExactlyWhenSpecified` | A role change succeeds exactly when the governor sets it for a non-zero address other than itself, and not a non-None role for the pending governor. |
| Registry | `check_createScope_acceptedExactlyWhenSpecified` | Creation succeeds exactly for a name of 1 to 128 bytes, 0 < `maxValidity` ≤ 365 days, and an id the caller has not used; the caller governs the new, empty scope. |
| Registry | `check_handover_acceptedExactlyWhenSpecified` | A proposal succeeds exactly from the governor for an address without a role; acceptance succeeds exactly from the pending governor, who then governs with no handover pending. |
| Registry | `check_currentPolicy_inForceExactlyBeforeExpiry` | At every later time the current version is reported in force exactly while `block.timestamp < expiresAt`. |
| Registry | `check_anyCall_keepsVersionsAndResolvedAppeals` | After any call, no stored word of either version in the fixture changes, rejected and accepted appeals keep their status and resolution, and an open appeal never returns to None. |
| Registry | `check_anyCall_governorHoldsNoRole` | After any call (including `proposeGovernor`, `acceptGovernor` and `setIssuer` with any arguments), neither the governor nor the pending governor holds an issuer role. |
| Anchor | `check_commitRoot_acceptedExactlyWhenSpecified` | `commitRoot` succeeds exactly when a publisher is appointed and is the caller, the UTC day has ended, the day is within the window or the window is unbounded, the day was never written, the root is not 0 and the URI is at most 256 bytes. On success the day holds the root, revision 0, not empty, committed at the block time. The zero address can never write, because an unappointed scope has a window of 0. |
| Anchor | `check_markEmpty_acceptedExactlyWhenSpecified` | The same rule without a root; on success the day is empty. |
| Anchor | `check_correctRoot_acceptedExactlyWhenSpecified` | A correction succeeds exactly from the scope's current governor in the registry, for a written day, with a different root, a non-zero reason and a URI of at most 256 bytes; the revision increases by one, the commit time is kept, and the day is empty exactly when the new root is 0. |
| Anchor | `check_setPublisher_acceptedExactlyWhenSpecified` | Appointment succeeds exactly from the current governor, with a window of 0 exactly for a revocation. |
| Anchor | `check_anyCall_writtenDaysChangeOnlyByGovernor` | After any call at any later time, a written day keeps its commit time, its revision never decreases, and its root or emptiness changes only if the caller is the governor. |
| Anchor (secondary) | `check_leaf_distinctRowsHaveDistinctLeaves`, `check_leaf_isNeverAnInternalNode` | Distinct rows give distinct leaves (units and categories of 0 to 2 bytes), and no leaf equals an internal node (including the lengths at which a leaf preimage is 65 bytes, as a node preimage is). Both rest on Halmos's model of keccak256 as injective, so they show that the encodings are unambiguous as byte strings, not anything about keccak256. |

## 5. Mutation testing

### 5.1 Targeted mutation check (CI)

[`scripts/mutation_check.py`](../../contracts/scripts/mutation_check.py) injects one bug at a time into a temporary copy of the contracts, never into the working tree, and runs the Foundry suite that should catch it with a shallow campaign (64 runs × 32 calls) under three fixed fuzzer seeds; the suite must fail under every seed, and a mutant that does not compile is an error, not a kill. The list has 26 mutants: 11 written with the suites and 15 proposed by a separate internal review of the first version of this document, which found that the Foundry suites then missed them (most were caught by the Hardhat tests). All 26 are caught. Because the suites were improved until these mutants died, this is a regression check, not a mutation score; §5.2 gives the score.

### 5.2 Mutation score over the whole test stack

Mutants generated by [slither-mutate](https://github.com/crytic/slither/wiki/Mutator) 0.11.3 (all mutators, `--comprehensive`), not chosen by us, run against the whole test stack: the Hardhat unit and EAS integration tests, then the Foundry suites with a shallow campaign and a fixed seed. A mutant is killed if any test fails. Mutants that do not compile and the three that leave the source unchanged are excluded.

| Contract | Mutants | Killed | Surviving |
| --- | --- | --- | --- |
| `IssuerRoleResolver` | 191 | 172 | 19 |
| `MetricsAnchor` | 224 | 205 | 19 |
| `VerifiablePolicyRegistry` | 369 | 338 | 31 |
| **Total** | **784** | **715 (91.2 %)** | **69** |

Every survivor was examined, and none changes observable behaviour:

- **62 equivalent.** Comparisons with zero on unsigned integers, `bytes32` and enums (`== 0` to `<= 0`, `!= 0` to `> 0`, `!= None` to `> None`); loop counters (`i++` to `++i`, `uint256 i = 0` to `uint256 i` or `uint128 i`, `i < n` to `i != n`); `constant` to `immutable` or a narrower type holding the same value; `storage` to `memory` for a read-only reference; `abi.encode` to `abi.encodePacked` of two `bytes32` values (identical bytes); a removed `return false` whose default is `false`; enum comparisons that coincide on the reachable values (`k == Deployment` to `k <= Deployment` with `Deployment = 0`); `lag <= NO_LAG_LIMIT`, after which `day + lag < today` can never hold.
- **5 equivalent until a date.** Timestamps narrowed to `uint32` (until 2106) and the day number to `uint16` (until 2149).
- **2 on the defence-in-depth check** in `acceptGovernor` (§7), which is unreachable by construction.

The first run, against the test suite as it was, left 15 behaviour-changing mutants alive. They showed real gaps, all closed with tests and confirmed by re-running every survivor against the current stack:

- events must name the calling contract (`msg.sender`), not `tx.origin`, since a governor is normally a Safe whose transactions are submitted by an owner's account;
- `ScopeCreated` and the arguments of `PolicyPublished`, including the expiry indexers read, were not asserted;
- the filing time of an appeal, and the `AppealNotOpen` selector for an unknown appeal (the mutants still reverted, with another error);
- batches with more values than attestations; the resolver's head-only check at exactly the head length; unit and category lengths up to the `uint16` limit; the `NO_LAG_LIMIT` and `MAX_URI_LENGTH` constants.

How the score was obtained, so that it can be reproduced: sources must be ASCII. slither-mutate 0.11.3 applies Slither's byte offsets with Python character slicing, so any non-ASCII character in a comment shifts every later mutant to the wrong place, and the tool then reports mutants as uncaught that were never applied; our first run was invalid for that reason, and CI now rejects non-ASCII sources. The command, from a copy of `contracts/` with a `run-tests.sh` that runs `npx hardhat test` and `forge test`, is `slither-mutate src --test-cmd ./run-tests.sh --comprehensive --compile-force-framework solc --solc-args "--optimize --optimize-runs 200 --evm-version cancun"`.

## 6. Integration with EAS

[`EasIntegration.test.js`](../../contracts/test/EasIntegration.test.js) deploys `SchemaRegistry` and `EAS` v1.4.0 from the published artifacts, registers the three VPR schemas with their resolvers and goes through `EAS.attest`, `multiAttest` and `revoke`: issuance only by the holder of the schema's role in the scope, refusal across scopes and after a role is withdrawn, revocation only by the attester, batches failing as a whole, malformed data and value refused. Attestation UIDs are read from the `Attested` event, since they depend on the block timestamp. [`scripts/check-eas.js`](../../contracts/scripts/check-eas.js) checks a deployment manifest against the chain: each schema UID is registered with the schema string and revocability of [`schemas/eas-schemas.json`](../../schemas/eas-schemas.json); its resolver is the manifest's, has the matching `SchemaKind`, points to the manifest's registry and EAS, and is not payable; and it reports the deployed EAS and SchemaRegistry versions.

## 7. Coverage

CI run [42795525989](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42795525989), Hardhat tests:

| Contract | Statements | Branches | Functions | Lines |
| --- | --- | --- | --- | --- |
| `IssuerRoleResolver` | 100 % | 100 % | 100 % | 100 % |
| `MetricsAnchor` | 100 % | 100 % | 100 % | 100 % |
| `VerifiablePolicyRegistry` | 100 % | 98.68 % | 100 % | 100 % |

CI fails if statements, lines or functions fall below 100 % or branches below 98 %. The one branch not covered is the role check in `acceptGovernor`. It is unreachable while `proposeGovernor` and `setIssuer` enforce the same rule, and is kept as defence in depth (marked in the source). Line and branch coverage say which code ran, not whether its effects were checked; §5 addresses that.

## 8. Gas

Measured by `hardhat-gas-reporter` over the unit tests in CI run [42795525989](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42795525989) (solc 0.8.24, 200 runs, `cancun`). Minimum and maximum include short and maximum-length (256-byte) URIs.

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

These are L2 execution gas figures. On OP Stack chains a transaction also pays an L1 data fee: since the Fjord upgrade it is computed from a FastLZ-based estimate of the compressed size of the full signed transaction, priced with the L1 base fee and the blob base fee; chains on the Isthmus upgrade may add an operator fee. Neither is included in this table. The recurring cost per scope and day is one `commitRoot` (or `markEmpty`). The table averages the unit tests' calls, whose URIs are mostly short. The one-year workload in [BENCHMARKS §2.1](../benchmarks/BENCHMARKS.md#21-one-year-of-one-scope-with-the-l1-data-fee) uses 66-byte `ipfs://` URIs, which take three storage slots more, and reports the L1 data fee read from OP Mainnet's oracle: for example, `commitRoot` costs 166 651 gas there, against the 116 835 average here.

## 9. Time and ordering on OP Stack

Two functions depend on block time: `MetricsAnchor` derives the UTC day from it, and `currentPolicy` compares it with expiry. The OP Stack derivation rules ([specification](https://specs.optimism.io/protocol/derivation.html); [Fjord](https://specs.optimism.io/protocol/fjord/derivation.html)) set each L2 block's timestamp to the previous one plus the block time and require `l1_origin.timestamp ≤ block.timestamp ≤ max(l1_origin.timestamp + max_sequencer_drift, prev_l2_timestamp + l2_block_time)`, with `max_sequencer_drift` = 1800 s since Fjord; a batch with transactions beyond the drift is dropped. The sequencer chooses the L1 origin and how fast it produces blocks. Consequently:

- **Accuracy.** Blocks that carry transactions are timestamped between their L1 origin and 1800 s after it, and the origin cannot be ahead of L1. L2 time can therefore run up to about 30 minutes ahead of wall-clock time; it can also lag, for example after a sequencer outage, when blocks with past timestamps are produced to catch up and may still carry transactions. The day number and expiry follow wall-clock UTC to about ±30 minutes in normal operation, with a larger lag possible after an outage.
- **Anchoring.** A sequencer, alone or colluding with the publisher, could let a day be anchored up to about 30 minutes before it ends in real time, with a release that misses its last events. The root would be public and attributable, and the governor can correct it. A delayed `commitRoot` can also cross the end of the back-fill window and be refused with `DayTooOld`; publishers should anchor well inside the window, which we recommend to be at least two days for operational scopes.
- **Expiry.** A version can be reported as expired up to about 30 minutes early, and a renewal submitted close to expiry can be included after it, leaving a gap in which the charter fallback applies. Renewal is a signed act before expiry (reason code 2, [GOVERNANCE](../GOVERNANCE.md)); a charter should schedule it days, not hours, ahead.
- **Censorship.** Transactions refused by the sequencer can be submitted as deposits through `OptimismPortal` on L1; the derivation rules force their inclusion, at the latest when the sequencing window (a deployment parameter, typically 12 hours) has elapsed. A deposit sent by an L1 contract arrives with an aliased sender (the address plus `0x1111000000000000000000000000000000001111`). The governor Safe on L2 can still be driven this way, because its `execTransaction` checks the owners' signatures, not the sender, so any L1 account can submit it; appeals can be filed by any L1 account; a publisher that is a contract cannot use a deposit directly, since the aliased address is not the publisher. Filtering itself does not depend on the chain's liveness.
- **Finality.** An L2 block is final when it is derived from finalized L1 blocks. Verifiers and the dashboard read state at the `finalized` block tag (or at least `safe`), and the deployment manifest states the tag verifiers use (`finality`).
- **Front-running.** Scope creation cannot be pre-empted, because the scope id binds the creator. An appeal hash seen in the mempool can be filed first by someone else, which only creates the same appeal (the filer is not recorded by design).

## 10. Not covered, and next steps

- No third-party audit (milestone M3, VPR-024). This document is input to it, not a substitute.
- No unbounded formal verification. The symbolic checks of §4.1 hold for every input within stated bounds, for one transaction from a fixed concrete state; they are not an induction over all reachable states, and sequences are covered by fuzzing only. A proof of the invariants of §4 over all reachable states (Certora, or Halmos with symbolic storage) remains to be done, as does any symbolic check of `IssuerRoleResolver` and of `verifyRow`'s node hashing.
- Event emission is tested in the unit tests, not in the invariant suites; indexers should rely on the events listed in [INTERFACES](../INTERFACES.md) and on reading state.
- The leaf encoding is checked by the shared cross-language vector (Python, Hardhat and Foundry) and by an independent leaf model in the anchor invariants; internal nodes by a Solidity reference model in the property fuzz tests. There is no cross-language differential fuzzing yet.
- `verifyRow` returns false for an empty day both because it checks the root and because a leaf hash is never zero; removing the explicit check is therefore an equivalent mutant that no test can catch.
- Gas costs of the planned ZK verifier are not known; they will be measured in M4.

## 11. Reproduce

```bash
cd contracts
npm ci
npx hardhat test                                   # unit and EAS integration tests
REPORT_GAS=1 npx hardhat test                      # gas table
npx hardhat coverage                               # coverage
FOUNDRY_PROFILE=ci forge test                      # fuzz and invariant tests (Foundry 1.3.5)
python3 scripts/mutation_check.py                  # targeted mutation check (temporary copy)
python3 scripts/symbolic_check.py                  # Halmos 0.3.3 symbolic checks; add --mutants for the mutant run
slither . --compile-force-framework hardhat --filter-paths "node_modules|test-foundry"   # Slither 0.11.3
```
