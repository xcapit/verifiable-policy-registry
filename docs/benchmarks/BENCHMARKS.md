# Benchmarks

*CC BY 4.0 · Every number below was measured on synthetic data, on the environment named next to it. None of them describe resolver latency, school-network performance or production costs.*

## How to reproduce

```bash
python tools/bench/bench_merkle.py                 # release construction and verification
E2E_OUT=out ./examples/e2e/run.sh                   # demo; gas is in out/evidence-manifest.json
cd contracts
npx hardhat run scripts/bench-workload.js           # one-year workload (section 2.1); writes workload-gas.json
OP_RPC_URL=<OP Mainnet RPC> node scripts/bench-l1fee.js   # L1 data fee, read-only (section 2.1)
```

CI runs the first two on every push and uploads them as the artifact `demo-evidence`. It also re-runs the workload and fails if its gas differs from the committed [`workload-gas.json`](workload-gas.json); the L1 fee step reads a public network and is run by hand.

## 1. Release construction and row verification (Python reference implementation)

Synthetic release with 5 categories per unit, one day. The root time is the best of 3 runs; the verification time is the best of 50 runs for one row.

**CI runner** (GitHub Actions `ubuntu-latest`, x86_64, Python 3.12.16), run [42642706736](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42642706736) on commit `93d7b44`:

| Rows | Root (s) | Verify one row (µs) | Proof length | Release CSV (bytes) |
| --- | --- | --- | --- | --- |
| 10 | 0.0001 | 24.7 | 4 | 359 |
| 100 | 0.001 | 38.2 | 7 | 3 347 |
| 1 000 | 0.01 | 52.2 | 10 | 33 227 |
| 10 000 | 0.0987 | 69.8 | 14 | 332 027 |
| 50 000 | 0.5017 | 78.5 | 16 | 1 660 027 |

**Maintainer workstation** (Apple M5 Pro, arm64, macOS, Python 3.14.5), 2026-11-09:

| Rows | Root (s) | Verify one row (µs) | Proof length | Release CSV (bytes) |
| --- | --- | --- | --- | --- |
| 10 | < 0.0001 | 9.3 | 4 | 359 |
| 100 | 0.0004 | 14.8 | 7 | 3 347 |
| 1 000 | 0.004 | 19.8 | 10 | 33 227 |
| 10 000 | 0.0407 | 26.0 | 14 | 332 027 |
| 50 000 | 0.1908 | 29.2 | 16 | 1 660 027 |

**Reading.** A pilot cohort of 50 schools with at most 10 published categories produces at most 500 rows per day. Building and verifying such a release takes milliseconds and needs a few tens of kilobytes. Root construction grows linearly, and proof length grows as ⌈log₂ n⌉.

## 2. Gas on the Hardhat EVM

From the gas reporter over the unit tests in CI run [42795525989](https://github.com/xcapit/verifiable-policy-registry/actions/runs/42795525989) (Hardhat 2.29.1, solc 0.8.24, optimizer 200 runs, `evmVersion: cancun`). Averages over the calls in the test suite; the full table with minimum and maximum (short and 256-byte URIs) is in [contract assurance §8](../security/CONTRACT_ASSURANCE.md#8-gas). Figures before the pre-audit hardening (v0.3) are superseded.

| Operation | Gas used (average) |
| --- | --- |
| `createScope` | 73 097 |
| `setIssuer` | 49 584 |
| `setPublisher` | 64 548 |
| `publishPolicy` | 152 795 |
| `fileAppeal` | 114 724 |
| `rejectAppeal` | 55 847 |
| `commitRoot` | 116 835 |
| `markEmpty` | 55 999 |
| `correctRoot` | 61 686 |

`verifyRow` is a view; the demo's evidence manifest reports an estimate for a three-step proof. These are EVM execution gas figures. On OP Mainnet a transaction also pays an L1 data fee that depends on the compressed size of the transaction and on L1 prices; it is measured for a one-year workload in §2.1. Converting to currency requires gas prices at the time of use, and is left to the [cost model](../giga/COST_MODEL_TEMPLATE.md).

**Per scope and day**, the recurring on-chain cost is one `commitRoot` (or `markEmpty`). Appeals and policy versions are occasional. Attestations are not: they scale with schools × versions (§2.1).

### 2.1 One year of one scope, with the L1 data fee

[`scripts/bench-workload.js`](../../contracts/scripts/bench-workload.js) runs one year of activity for one scope on the Hardhat EVM and records every transaction. The workload is an **assumption, not pilot data**; its parameters are at the top of the script and in [`workload-gas.json`](workload-gas.json):
- 50 schools;
- a root every school day and an empty day at weekends;
- a renewal every 30 days, with a validity of 45 days;
- 24 appeals, one in three accepted by a new version, and 4 rejected documents filed again;
- 2 corrections;
- for every version in force, one `multiAttest` of the 50 deployments by the operator and 50 single independent-test attestations by the reviewer (INTERFACES I8).

That gives 20 policy versions and 1 456 transactions.

Inputs are realistic in size and entropy:
- hashes are keccak-256 outputs;
- URIs are 66-byte `ipfs://` CIDv1 strings;
- transactions are serialised as EIP-1559 transactions for chain id 10.

Short or repetitive inputs would understate both gas and compressed size. Execution gas is deterministic for these inputs, so CI checks it exactly.

The L1 data fee is read from OP Mainnet's own `GasPriceOracle` predeploy by [`scripts/bench-l1fee.js`](../../contracts/scripts/bench-l1fee.js). The script makes read-only calls with the synthetic transactions; no key and no transaction is involved.
- **Calibration.** The oracle's estimate from an unsigned serialization was compared with the receipts of 20 recent mainnet transactions (blocks 159 377 635–636). It is within 0.87 % of the receipt's `l1GasUsed` at the median, and within 1.46 % at most.
- **Snapshots.** Fees were read at 7 blocks one day apart, from 159 118 436 (2026-11-04) to 159 377 636 (2026-11-10), with the oracle in Fjord mode. The fees below are medians over these snapshots, with the range in brackets.
- **Scalars and prices.** Over the period the scalars were 5 227 (base fee) and 1 014 213 (blob base fee). The L1 base fee was 0.033–0.112 gwei and the L2 base fee 300–687 wei.
- **Excluded.** Priority fees are excluded. No operator-fee fields appeared in the receipts examined.

| Operation | Sender | Per year | Execution gas (min / median / max) | Tx bytes | L1 gas | L1 fee, gwei | L2 base fee, gwei |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `commitRoot` | publisher | 260 | 166 627 / 166 651 / 166 651 | 305 | 2 838 | 1.158 [0.864–3.019] | 0.063 |
| `markEmpty` | publisher | 105 | 56 106 | 111 | 1 600 | 0.652 [0.487–1.702] | 0.021 |
| `publishPolicy` | governor | 20 | 176 165 / 196 449 / 227 657 | 400 | 3 387 | 1.381 [1.031–3.603] | 0.075 |
| `rejectAppeal` | governor | 16 | 55 835 / 55 847 / 55 847 | 110 | 1 754 | 0.715 [0.534–1.866] | 0.021 |
| `correctRoot` | governor | 2 | 64 187 | 336 | 3 280 | 1.338 [0.998–3.489] | 0.024 |
| `setIssuer` | governor | 3 | 51 437 / 51 449 / 51 449 | 141 | 1 781 | 0.726 [0.542–1.895] | 0.020 |
| `createScope`, `setPublisher` | governor | 1 each | 71 403; 75 143 | 174; 142 | 1 600; 1 794 | 0.652; 0.732 | 0.027; 0.029 |
| `fileAppeal` (round 1; round 2) | anyone | 24; 4 | 118 910; 104 301 | 110 | 1 754 | 0.715 [0.534–1.866] | 0.045; 0.040 |
| `attest` IndependentTest, one school | reviewer | 1 000 | 455 241 / 455 277 / 455 277 | 754 | 3 454 | 1.409 [1.051–3.674] | 0.173 |
| `multiAttest` Deployment, 50 schools | operator | 20 | 14 300 332 / 14 300 932 / 14 300 932 | 24 241 | 14 603 | 5.955 [4.444–15.533] | 5.449 |

Per year and scope, at the median snapshot prices:

| Sender | Transactions | Execution gas | L1 fee, gwei | L2 base fee, gwei | Total, gwei |
| --- | --- | --- | --- | --- | --- |
| Publisher (exact) | 365 | 49 219 982 | 369.5 | 18.8 | 388.2 |
| Governor (lower bound, see below) | 43 | 5 324 975 | 45.3 | 2.0 | 47.3 |
| Reviewer | 1 000 | 455 274 780 | 1 408.6 | 173.5 | 1 582.1 |
| Operator | 20 | 286 016 840 | 119.1 | 109.0 | 228.1 |
| Appellants | 28 | 3 271 032 | 20.0 | 1.2 | 21.3 |

**Reading.**
- **The L1 data fee dominates.** For every operation except the 50-school batch it is 8 to 55 times the L2 execution fee at these prices. It is set by the transaction's compressed size, so it is the quantity to watch. Short transactions sit at the 100-byte floor of the Fjord formula (1 600 L1 gas).
- **Attestations dominate the volume.** They account for 93 % of the execution gas and 80 % of the fees, because INTERFACES I8 asks for an independent test per school *for each version in force*. With a renewal every 30 days, that is 1 000 reviewer attestations a year for 50 schools. A renewal that does not change the content (reason code 2) therefore had a real cost at the edge. [ADR-0012](../adr/0012-tests-survive-renewals.md) now keeps a test valid across versions with the same rules digest, so in this workload only the 8 versions that change the rules (the initial one and the 7 appeals accepted within the year) need new tests: 400 reviewer attestations instead of 1 000, about 182 million gas instead of 455 million. The committed workload still measures the earlier rule (`attestEveryVersion`), so that the two can be compared.
- **Governor figures are lower bounds.** The governor is a Safe, and a Safe adds `execTransaction` with *m* signature checks and the signatures' calldata; that overhead is not measured here.
- **The deployment batch is large.** The 50-school `multiAttest` is a single transaction of 14.3 million gas, about 286 000 per school. Batch size was not varied.
- **Prices move.** Absolute amounts in gwei hold for this week's prices only. The execution gas and L1 gas columns do not depend on prices; the fees scale linearly with the L1 base fee, the blob base fee and the L2 base fee. Conversion to currency is left to the [cost model](../giga/COST_MODEL_TEMPLATE.md).

## 3. Demonstrator duration and data volume

The `e2e` job, including `npm ci`, compilation and both stages, completes in a few minutes on the CI runner; the precise duration is in the job log of the run above. The demo writes about 15 KB of artefacts: release CSVs, zone, JSON inputs and the manifest.

## 4. Not measured

- **Resolver latency impact.** No resolver runs in the demo (zone evaluation only). Measuring it is planned with the pinned resolver container (VPR-019) and at alpha onboarding.
- **Network needs at schools.** These are measured during the alpha (Gate B).
- **Safe overhead.** The cost of `execTransaction` and of *m* signatures for governor transactions (§2.1) is not measured.
- **Conformance attestations, revocations and `verifyRow` calls** are not in the workload; `verifyRow` is a view and costs nothing unless it is called from a contract.

## Planned ZK benchmarks

To be run in M4 (VPR-036) before the proving-system decision is confirmed:
- prover time and peak memory for a worst-case day: 50 schools, all categories, realistic event counts, on stated commodity hardware;
- proof size;
- off-chain verification time;
- on-chain verification gas on OP Sepolia;
- per-school proving as the fallback, with the same metrics.

Results will be reported with the environment, as above.
