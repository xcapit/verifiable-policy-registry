// SPDX-License-Identifier: AGPL-3.0-only
// L1 data fee of the workload's transactions on OP Mainnet, from the chain's own GasPriceOracle predeploy
// (0x420000000000000000000000000000000000000F). READ-ONLY: eth_call and block reads only; no key, no
// transaction. The transactions are the synthetic ones recorded by scripts/bench-workload.js.
//
// 1. Calibration. For up to CALIB_N recent mainnet transactions, the oracle's estimate from the unsigned
//    serialization is compared with the l1GasUsed and l1Fee in the transaction's own receipt.
// 2. Snapshots. For each operation's representative transaction, l1GasUsed (set by the bytes alone) and
//    l1Fee are read at SNAPSHOTS blocks one day apart, ending at the latest block, together with the L2 base
//    fee; the median over the snapshots is reported. Fees are in wei; conversion to currency is left to the
//    cost model (docs/giga/COST_MODEL_TEMPLATE.md).
//
// Usage (from contracts/): OP_RPC_URL=<OP Mainnet RPC> node scripts/bench-l1fee.js
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const RPC = process.env.OP_RPC_URL;
const FILE = process.env.BENCH_OUT || path.join(__dirname, "..", "..", "docs", "benchmarks", "workload-gas.json");
const SNAPSHOTS = Number(process.env.SNAPSHOTS || 7);
const CALIB_N = Number(process.env.CALIB_N || 20);
const BLOCKS_PER_DAY = 43200; // 2-second L2 blocks
const ORACLE = "0x420000000000000000000000000000000000000F";
const ABI = [
  "function getL1Fee(bytes) view returns (uint256)",
  "function getL1GasUsed(bytes) view returns (uint256)",
  "function isFjord() view returns (bool)",
  "function l1BaseFee() view returns (uint256)",
  "function blobBaseFee() view returns (uint256)",
  "function baseFeeScalar() view returns (uint32)",
  "function blobBaseFeeScalar() view returns (uint32)",
];

const med = (xs) => {
  const s = [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return s[Math.floor((s.length - 1) / 2)]; // lower median, exact for bigint
};

async function calibrate(p, oracle, latest) {
  const rows = [];
  for (let b = latest; b > latest - 200 && rows.length < CALIB_N; b--) {
    const blk = await p.getBlock(b, true);
    for (const t of blk.prefetchedTransactions) {
      if (rows.length >= CALIB_N || t.type !== 2 || ethers.dataLength(t.data) < 150) continue;
      const r = await p.send("eth_getTransactionReceipt", [t.hash]);
      if (BigInt(r.l1GasUsed) <= 1600n) continue; // at the 100-byte floor the comparison says nothing
      const u = ethers.Transaction.from(t).unsignedSerialized;
      const g = await oracle.getL1GasUsed(u, { blockTag: b });
      rows.push({ block: b, inputBytes: ethers.dataLength(t.data), receipt: Number(r.l1GasUsed), oracle: Number(g) });
    }
  }
  const dev = rows.map((x) => Math.abs(x.oracle - x.receipt) / x.receipt).sort((a, b) => a - b);
  return {
    method: "getL1GasUsed(unsigned serialization) at the transaction's block, against the receipt's l1GasUsed",
    transactions: rows.length,
    blocks: [rows[rows.length - 1].block, rows[0].block],
    medianAbsDeviationPct: +(100 * dev[Math.floor((dev.length - 1) / 2)]).toFixed(2),
    maxAbsDeviationPct: +(100 * dev[dev.length - 1]).toFixed(2),
  };
}

async function main() {
  if (!RPC) throw new Error("set OP_RPC_URL to an OP Mainnet RPC endpoint");
  const p = new ethers.JsonRpcProvider(RPC, 10, { staticNetwork: true });
  const oracle = new ethers.Contract(ORACLE, ABI, p);
  const data = JSON.parse(fs.readFileSync(FILE, "utf8"));
  const latest = await p.getBlockNumber();

  const calibration = await calibrate(p, oracle, latest);

  const snapshots = [];
  for (let i = SNAPSHOTS - 1; i >= 0; i--) {
    const b = latest - i * BLOCKS_PER_DAY;
    const blk = await p.getBlock(b);
    const t = { blockTag: b };
    if (!(await oracle.isFjord(t))) throw new Error(`block ${b}: oracle not in Fjord mode; the fee formula differs`);
    snapshots.push({
      block: b,
      time: new Date(blk.timestamp * 1000).toISOString(),
      l2BaseFeeWei: blk.baseFeePerGas.toString(),
      l1BaseFeeWei: (await oracle.l1BaseFee(t)).toString(),
      blobBaseFeeWei: (await oracle.blobBaseFee(t)).toString(),
      baseFeeScalar: Number(await oracle.baseFeeScalar(t)),
      blobBaseFeeScalar: Number(await oracle.blobBaseFeeScalar(t)),
    });
  }

  const operations = {};
  for (const [op, v] of Object.entries(data.operations)) {
    const l1GasUsed = [], l1Fee = [], l2Fee = [];
    for (const s of snapshots) {
      const t = { blockTag: s.block };
      l1GasUsed.push(await oracle.getL1GasUsed(v.representativeTx, t));
      l1Fee.push(await oracle.getL1Fee(v.representativeTx, t));
      l2Fee.push(BigInt(v.gas.median) * BigInt(s.l2BaseFeeWei));
    }
    operations[op] = {
      l1GasUsed: Number(med(l1GasUsed)),
      l1FeeWei: { min: l1Fee.reduce((a, x) => (x < a ? x : a)).toString(), median: med(l1Fee).toString(), max: l1Fee.reduce((a, x) => (x > a ? x : a)).toString() },
      l2BaseFeeWei: { median: med(l2Fee).toString() },
    };
  }

  data.l1 = {
    network: "OP Mainnet (chain id 10)",
    oracle: `GasPriceOracle ${ORACLE}, Fjord formula`,
    note: "Read-only snapshot of public chain parameters. l1GasUsed depends only on the transaction bytes; the fees depend on L1 and L2 prices at each block and change over time. Priority fees are excluded.",
    calibration,
    snapshots,
    operations,
  };
  fs.writeFileSync(FILE, JSON.stringify(data, null, 2) + "\n");
  console.log(JSON.stringify({ calibration, snapshots: snapshots.map((s) => s.time) }, null, 1));
  for (const [op, v] of Object.entries(operations)) {
    console.log(`${op.padEnd(46)} l1GasUsed ${String(v.l1GasUsed).padStart(7)}  l1Fee median ${v.l1FeeWei.median.padStart(14)} wei  l2 base ${v.l2BaseFeeWei.median.padStart(14)} wei`);
  }
}

main().catch((e) => {
  console.error(e.shortMessage || e.message);
  process.exit(1);
});
