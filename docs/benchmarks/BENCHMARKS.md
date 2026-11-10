# Benchmarks

*CC BY 4.0 · Every number below was measured on synthetic data, on the environment named next to it. None of them describe resolver latency, school-network performance or production costs.*

## How to reproduce

```bash
python tools/bench/bench_merkle.py                 # release construction and verification
E2E_OUT=out ./examples/e2e/run.sh                   # demo; gas is in out/evidence-manifest.json
```

CI runs both on every push and uploads them as the artifact `demo-evidence`.

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

`verifyRow` is a view; the demo's evidence manifest reports an estimate for a three-step proof. These are EVM execution gas figures. On OP Mainnet a transaction also pays an L1 data fee that depends on calldata size and L1 prices; it is not included. Converting to currency requires gas prices at the time of use, and is left to the [cost model](../giga/COST_MODEL_TEMPLATE.md).

**Per scope and day**, the recurring on-chain cost is one `commitRoot` (or `markEmpty`). Appeals, policy versions and attestations are occasional.

## 3. Demonstrator duration and data volume

The `e2e` job, including `npm ci`, compilation and both stages, completes in a few minutes on the CI runner; the precise duration is in the job log of the run above. The demo writes about 15 KB of artefacts: release CSVs, zone, JSON inputs and the manifest.

## 4. Not measured in v0.3

- **Resolver latency impact.** No resolver runs in the demo (zone evaluation only). Measuring it is planned with the pinned resolver container (VPR-019) and at alpha onboarding.
- **Network needs at schools.** These are measured during the alpha (Gate B).

## Planned ZK benchmarks

To be run in M4 (VPR-036) before the proving-system decision is confirmed:
- prover time and peak memory for a worst-case day: 50 schools, all categories, realistic event counts, on stated commodity hardware;
- proof size;
- off-chain verification time;
- on-chain verification gas on OP Sepolia;
- per-school proving as the fallback, with the same metrics.

Results will be reported with the environment, as above.
