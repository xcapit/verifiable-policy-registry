# Zero-knowledge and cryptographic evidence

*CC BY 4.0 · v0.3 · Authoritative specification of every encoding and commitment in VPR, and of the planned zero-knowledge relation. Status words: **Implemented** (code and passing tests), **Designed** (specified here, not implemented), **Planned** (future milestone).*

> **Summary of status.** Policy hashing, release encoding, Merkle construction and on-chain row verification are **Implemented**, and the same test vector passes in Solidity and Python. The event-log commitment, the zero-knowledge relation, the prover and the on-chain proof verifier are **Designed** in this document and **Planned** for milestone M4 on testnet ([ROADMAP](../ROADMAP.md)). No audit and no formal verification has taken place.

## 1. Notation and primitives

- `H(x)` is keccak-256 as used by Ethereum (not NIST SHA3-256). `‖` is byte concatenation. Integers are big-endian, unsigned, with the stated width.
- `utf8(s)` is the UTF-8 encoding of a string, without a terminator.
- Hex values are written `0x`-prefixed and lowercase.
- Domain-separation tags: `0x00` release leaf, `0x01` Merkle internal node, `0x02` event leaf (Designed), `0x03` set-commitment leaf (Designed), `0x04` log commitment (Designed). Each tag has exactly one role.

Assumptions: H is collision-resistant and second-preimage-resistant. Where it is used with a secret 256-bit salt it is treated as a hiding commitment, which assumes H behaves as a random oracle. That is standard, but it is a heuristic, not a proof.

## 2. Policy document and content hash · Implemented

- Canonical form: JSON with lexicographically sorted keys, separators `,` and `:` without whitespace, UTF-8, non-ASCII kept, after validation (domains lower-cased, trailing dot removed). Implementation: `tools/vpr/policy.py` (`canonical_json`, `content_hash`) and `tools/vpr/toolkit.py` (`canonical_json`, `document_hash`).
- `contentHash = H(canonical_json(document))`; `scopeId = H(abi.encode(governor, scope))`, computed on-chain by `scopeIdOf` (from v0.4; v0.3.0 and earlier used `H(utf8(scope))`).
- **What the hash binds.** Every field of the document: scope, version, profile, categories, `valid_days`, `reason_code`, threat feeds by provider and version, local blocks and exceptions with reasons, and `restricted_list_hash`.
- **What binds the document to the chain.** The governor's `publishPolicy(scopeId, contentHash, …, validity, …)` call. **Gap.** Nothing checks on-chain that `validity` equals `valid_days × 86400`, or that the version number in the document equals the on-chain version. `vpr policy-hash` lets anyone check the content hash. The equality checks for validity and version are planned as VPR-060, used by the sync daemon (VPR-015) and the dashboard (VPR-021).
- **What the hash does not bind.** Threat feeds are referenced by provider and version strings only, so the hash does not bind the feed contents, and therefore not the effective block set. The `; policy content hash` line in a compiled zone is self-asserted by whoever compiled it. Binding feed contents (a hash per feed in `threat_feeds`) and the produced zone (`resolverConfigHash` in the deployment attestation) is Planned (VPR-065).
- **Restricted list.** `restrictedListHash = H(utf8(join("\n", sorted(unique(normalised domains)))))`. It is a binding commitment, but **not hiding**: the list is low-entropy, and anyone who holds a candidate list can test it. It proves which list was declared, not that it was enforced (§9). `vpr compile-rpz` refuses a restricted file whose hash differs from the declared one (test: `test_restricted_list_must_match_the_declared_hash`).

## 3. Release encoding and Merkle tree · Implemented (dataset format `vpr-dataset/2`)

**Row.** `(unit_id, day, category, count)`. `unit_id` is a public institutional identifier (a Giga school id, a district, …). `day` is an ISO date in UTC. `count` is an integer ≥ *k*.

**Leaf.** `leaf = H(0x00 ‖ dayNumber:uint32 ‖ count:uint256 ‖ len(unit):uint16 ‖ utf8(unit_id) ‖ len(cat):uint16 ‖ utf8(category))`, where `dayNumber` is the number of days since 1970-01-01. The length prefixes make the encoding injective. The day number binds a row to one anchored day. Fields longer than 65 535 bytes are rejected: `FieldTooLong` on-chain, `ValueError` off-chain.

**Tree.**
- Leaves are taken in release order: rows sorted by `(unit_id, day, category, count)`.
- An internal node is `H(0x01 ‖ min(a, b) ‖ max(a, b))`. The children are sorted, so proofs need no position bits.
- An odd node at any level is promoted unchanged.
- A release covers exactly one day, and its cells `(unit_id, day, category)` are unique. A release with no rows has no root and is never anchored.
- A proof is the list of sibling hashes from leaf to root.

**Verification.** `MetricsAnchor.verifyRow(scopeId, day, unitId, category, count, proof)` computes the leaf from the row and the anchored day, then folds the proof. It accepts rows, not raw leaves. A leaf-only interface would accept an internal node with a shortened proof even with domain separation, so the contract does not offer one. Off-chain equivalents: `vpr.toolkit.verify_row`, and `vpr prove-row` / `vpr verify-row`.

**Shared test vector** (Solidity `contracts/test/MetricsAnchor.test.js`, Python `tools/tests/test_metrics.py`):

| Rows (day 2026-11-01 = 20758) | Value |
| --- | --- |
| `giga-0001, adult, 40` → leaf | `0xd16b6d8f55bf68aa54ca8d755e0c0beb5c84c2e63e9eda7ab55abc5579b8a348` |
| root of `[giga-0001 adult 40, giga-0001 malware 25, giga-0003 malware 25]` | `0x7d91cbb18fd37a7042393e2043b2fed8a1d0723bdf8845d72bc7188febdf6747` |

Negative tests, all passing:

| Case | On-chain | Off-chain |
| --- | --- | --- |
| Tampered count | ✓ | ✓ |
| Same row claimed for another day | ✓ | ✓ |
| Unanchored day | ✓ | n/a |
| Wrong root | n/a | ✓ |
| Over-long field | ✓ | n/a |
| Rewrite of an anchored day | ✓ | n/a |
| Duplicate cells | n/a | ✓ |
| Release spanning several days | n/a | ✓ |
| Non-integer or non-positive count | n/a | ✓ |

**Write-once.** `commitRoot` reverts with `DayAlreadyCommitted` once a (scope, day) is anchored. Corrections are not possible on-chain. A correction must be published as a new release under a documented procedure, which is Planned with the dashboard (VPR-021).

## 4. Aggregation and suppression · Implemented

`Agg_k(L)` counts events per `(unit_id, day, category)` and keeps cells with count ≥ *k* (pilot default *k* = 10). Implementation: `metrics.aggregate`, `toolkit.aggregate`. The number of suppressed cells is not returned by the toolkit and not published (tests in `tools/tests/test_privacy.py`). What suppression does and does not protect is analysed in the [privacy analysis](../privacy/PRIVACY_AND_REIDENTIFICATION_ANALYSIS.md). Suppression is not *k*-anonymity and not differential privacy.

## 5. Event log and its commitment · Designed

The resolver exporter (VPR-016, Planned) emits events `e_j = (unit_id, day, category)`. The log of a day is `L = ⟨e_1, …, e_m⟩` in arrival order.

**Event leaf.** `ev_j = H(0x02 ‖ scopeId:bytes32 ‖ dayNumber:uint32 ‖ j:uint32 ‖ len ‖ utf8(unit_id) ‖ len ‖ utf8(category) ‖ s_j)`, with a fresh 256-bit salt `s_j` drawn from a CSPRNG by the exporter. The scope is part of the leaf so that relation (b) below can check it.

**Log commitment.** `C_L = H(0x04 ‖ MR(ev_1 … ev_m) ‖ r)`, where `MR` uses the node rule of §3 and `r` is a fresh 256-bit salt. The number of events *m* is **not** public: it is part of the witness and bound inside the proof. Publishing *m* would reveal `m − Σ published counts`, the exact number of events in suppressed cells. With one suppressed cell in a scope and day, that is the cell's value.

**Properties.** Binding follows from collision resistance. Hiding follows from the salts, under the random-oracle heuristic. Without salts, `C_L` would be an unsalted hash of a small, structured set whose large cells are public, and the suppressed cells could be recovered by enumeration. Per-event salts also allow a selective opening of a single event (§8) without revealing the others.

**Anchoring.** `C_L` is anchored with the daily root. The current `MetricsAnchor` has no field for it: a contract change is Planned in M4 (VPR-058).

## 6. The zero-knowledge relation · Designed

**Public inputs** `x`:
1. `domain` = `H(utf8("VPR-AGG-v1") ‖ chainId:uint256 ‖ verifier:address ‖ anchor:address)`. This binds the proof to one deployment and prevents replay on another chain or contract.
2. `scopeId`, `dayNumber`.
3. `policyVersion`, `contentHash` of that version, and `catRoot`, a commitment to its category set (below).
4. `unitRoot`, a commitment to the set of units (schools) admitted to the scope on that day.
5. `k`, read by the verifier contract from the registry for `(scopeId, policyVersion)`, never supplied by the prover. Otherwise a prover could choose *k* = 1 and the proof would still verify.
6. `C_L` (§5) and `root`, the release root (§3).
7. `formatVersion` = 2.

**Witness** `w`: the events `e_1 … e_m`, the salts `s_1 … s_m`, and the membership paths of every event's category in `catRoot` and of its unit in `unitRoot`.

**Relation.** `R(x; w)` holds iff all of the following hold:

- (a) `C_L` is the commitment of §5 to `(e_j, s_j)_{j ≤ m}`;
- (b) every `e_j` has `day = dayNumber` and `scope = scopeId`, its category is a member of `catRoot`, and its unit is a member of `unitRoot`;
- (c) `root = MR(sorted rows of Agg_k(L))` with the leaf and node rules of §3;
- (d) the release is non-empty. An empty release has no root and is never anchored (§3); a day without a release is visible as a missing commitment.

**Binding the category set to the policy.** `catRoot = MR_0x03(sorted utf8(category))`. Recomputing `contentHash` over the full canonical JSON inside a circuit is expensive, so the design moves the binding on-chain instead. The governor records `catRoot` (and `unitRoot` per scope) in the registry next to each version. The verifier contract reads both from the registry for `(scopeId, policyVersion)`, so they are never supplied by the prover. A tool (`vpr policy-hash --json`, extended in M4) and the dashboard check that `catRoot` matches the categories of the published document. This makes the binding enforced on-chain and the document check independently verifiable. It requires a registry change (VPR-058), which also records `k` per version.

**Replay and substitution.** `domain`, `scopeId`, `dayNumber`, `policyVersion` and `k` are public inputs read by the verifier contract from its own context and the registry. A proof for another day, scope, chain or policy therefore fails.

## 7. What is hidden and what is not

| Item | Hidden from the public? |
| --- | --- |
| Cells below *k*, their values, and how many there are | Hidden, provided *m* stays private (§5) |
| Order and timing of events within a day | Hidden |
| Published cells (unit, day, category, count) | Public by design |
| Number of events *m* in the log | Hidden: a private witness bound in the proof (publishing it would reveal the total of suppressed cells) |
| Whether a unit had any event on a day | Partly revealed by published cells; the absence of a row does not reveal whether the unit had 0 or fewer than *k* events |

## 8. Canary events · Designed

Canaries are a **sampling check against omission, not a proof of completeness**. The reviewer generates queries from known units on undisclosed days. If they are recorded honestly, each produces an event. The reviewer cannot identify its own events in the log without a tag, and a tag visible to the operator would let the operator treat canaries specially. The design therefore uses count-level checks. After a release, the operator proves in zero knowledge that the count of cell `(u, d, c)` in `L` is at least the number of canaries the reviewer sent for that cell. This works whether or not the cell was published. An operator that drops all events it cannot rule out as canaries is caught with a probability that depends on the canary rate and on how indistinguishable canaries are from real traffic. The specification of that probability is part of VPR-038 (Planned).

Canaries cannot detect fabricated additional events, and they cannot detect omissions in cells the reviewer did not sample.

## 9. Risk register

| Risk | Status today | Mitigation | Residual |
| --- | --- | --- | --- |
| Replay of a root or proof on another day, scope or chain | Mitigated for roots (day in leaf; the publisher anchors each scope/day once, and only public governor corrections follow); Designed for proofs | `domain`, scope and day as public inputs read on-chain | Low once implemented |
| Substitution of the policy document | Mitigated | `contentHash` on-chain; `vpr policy-hash` | Document availability (mirrors) |
| Equivocation (different releases shown to different people) | Partly mitigated | One root per scope/day on a public chain; dataset URI on-chain | Off-chain hosts can serve different files; anyone can detect this by recomputing the root |
| Truncation or omission of events before aggregation | **Not mitigated cryptographically** | Reviewer tests; canaries (Designed); audit | High until canaries and TEE work exist |
| Fabricated events | **Not mitigated cryptographically** | Reviewer tests; audit | High |
| Malformed rows (duplicates, several days, bad counts, ambiguous encodings) | Mitigated | Validation and length-prefixed encoding; tests | Low |
| Internal node presented as a row | Mitigated | `verifyRow` hashes rows | Low |
| Restricted list declared but not enforced | **Not mitigated cryptographically** | Compile-time hash check; confidential auditor verification (Planned) | Medium |
| Low-entropy commitments brute-forced | Inherent to the restricted-list hash; mitigated for the event log by salts | Salted design (§5) | Restricted list remains testable by anyone holding candidates |
| Prover soundness bug or setup compromise | n/a (no prover) | Choice in §10; external audit of the circuit in phase 2 | Unknown until implemented |

## 10. Proving-system decision record · Open (decision due in M1, week 3)

| Option | For | Against |
| --- | --- | --- |
| zkVM running the reference relation (e.g. SP1 or RISC Zero), wrapped into a Groth16 or PLONK proof for the EVM | Reuses the Python oracle's logic in Rust; accelerated keccak in some zkVMs; fastest to correct code | Larger proving cost; trust in the zkVM and the wrapping circuit; universal or per-circuit setup depends on the wrapper |
| Dedicated circuit (Circom/Groth16, Halo2, Noir) with a SNARK-friendly hash for the event log | Cheapest proving and verification | Keccak release root is expensive in-circuit; more custom code to audit; Groth16 needs a per-circuit trusted setup |

Criteria:
- proving time for a worst-case day of 50 schools on commodity hardware;
- on-chain verification gas on OP Mainnet;
- setup assumptions;
- auditability of the circuit and of the toolchain;
- licence compatibility with AGPL-3.0.

The benchmark plan is in [BENCHMARKS](../benchmarks/BENCHMARKS.md#planned-zk-benchmarks). Until the decision is taken, **no trusted-setup assumption is made**. If Groth16 is chosen, the setup ceremony and its participants become part of this document.

## 11. On-chain verifier and gas

| Component | Status | Gas evidence |
| --- | --- | --- |
| `MetricsAnchor.verifyRow` (view) | Implemented | Estimated by the demo on the Hardhat EVM; see [BENCHMARKS](../benchmarks/BENCHMARKS.md) |
| `commitRoot`, `publishPolicy`, `fileAppeal`, `rejectAppeal` | Implemented | Gas used is recorded in the demo evidence manifest |
| ZK verifier | Designed | None |

Supported chains: none deployed. The contracts are EVM-portable. OP Sepolia is the M2 target and OP Mainnet is gated on the audit (Gate C).

## 12. Correctness versus truth

Everything in §3–§6, once implemented, establishes the **correctness of a computation over committed data**. That covers four things: the published figures are the suppressed aggregation of a committed log; that log contains only events from admitted units and approved categories; nothing was altered after anchoring; and every row can be checked individually. It does **not** establish that the log is a complete or truthful record of what the resolver did. That gap is covered only by institutional controls (independent tests, audit) and, partly, by canaries (§8).

## 13. Independent verification procedure (implemented parts)

```bash
pip install -e tools
vpr policy-hash policies/example-primary.yaml --json        # compare contentHash with the registry
vpr verify-root <release.csv> <root read from MetricsAnchor.getCommitment>
vpr prove-row <release.csv> --index 0 > proof.json
vpr verify-row proof.json --root <anchored root>             # exit 0 = match, 1 = mismatch
cd tools && python -m pytest -q tests/test_metrics.py       # includes the shared test vector
```

The end-to-end demonstrator (`examples/e2e/run.sh`) performs all of these against a local chain and writes an evidence manifest.
