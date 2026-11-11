// SPDX-License-Identifier: AGPL-3.0-only
// One year of on-chain activity for one scope, under an ASSUMED workload (parameters below), on Hardhat's
// in-process EVM with the same compiler settings as the deployment. Records the execution gas and the
// serialized transaction of every call, and summarises them per operation (count, min, median, max).
//
// Execution gas is deterministic for the given inputs, so the result is compared exactly with the committed
// file in CI (BENCH_CHECK=1). The L1 data fee is computed separately by scripts/bench-l1fee.js.
//
// Usage (from contracts/):
//   npx hardhat run scripts/bench-workload.js                       # writes BENCH_OUT (default below)
//   BENCH_CHECK=1 npx hardhat run scripts/bench-workload.js         # fails if the gas differs from BENCH_OUT
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const { ethers } = hre;
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const EAS_ARTIFACT = require("@ethereum-attestation-service/eas-contracts/artifacts/contracts/EAS.sol/EAS.json");
const REGISTRY_ARTIFACT = require("@ethereum-attestation-service/eas-contracts/artifacts/contracts/SchemaRegistry.sol/SchemaRegistry.json");
const { EAS_SCHEMAS, schemaUid } = require("./lib/eas-check");

// ------------------------------------------------------------------ assumed workload (not pilot data)
const W = {
  days: 365, // one year of daily anchoring
  schools: 50, // pilot cohort (docs/benchmarks/BENCHMARKS.md section 1)
  closedWeekdays: [0, 6], // Sunday and Saturday: nothing publishable, the publisher marks the day empty
  renewalEveryDays: 30, // scheduled renewal (reason code 2)
  versionValidityDays: 45, // each version stays in force 45 days; maxValidity of the scope is 90 days
  appealsPerYear: 24, // spread evenly
  acceptEvery: 3, // every third appeal is accepted by a new version (reason code 3), the others rejected
  appealDecisionDays: 14,
  resubmissions: 4, // rejected documents filed again (round 2)
  correctionsPerYear: 2,
  // Attestations (INTERFACES I8): for each version in force, the operator attests the deployment of every
  // school in one multiAttest, and the reviewer attests each school's independent test individually.
  attestEveryVersion: true,
};
const START = BigInt(Date.UTC(2027, 0, 4) / 1000); // Monday 2027-01-04 00:00 UTC
const DAY = 86400n;
const OUT = process.env.BENCH_OUT || path.join(__dirname, "..", "..", "docs", "benchmarks", "workload-gas.json");

// High-entropy deterministic values, so the serialized transactions compress like real ones.
const h = (s) => ethers.id(`vpr-bench:${s}`);
const B32 = "abcdefghijklmnopqrstuvwxyz234567";
function cid(s) {
  // CIDv1, base32, dag-pb/sha2-256: "bafybei" + 52 base32 characters (59 characters), as IPFS gateways print it.
  const bytes = ethers.getBytes(h(`cid:${s}`));
  let out = "bafybei";
  for (let i = 0; out.length < 59; i++) out += B32[bytes[i % 32] % 32];
  return `ipfs://${out}`;
}

const records = [];
async function send(op, actor, txPromise) {
  const tx = await txPromise;
  const receipt = await tx.wait();
  const gasUsed = Number(receipt.gasUsed);
  // The transaction as it would be sent on OP Mainnet (chain id 10, EIP-1559), unsigned: the L1 fee oracle
  // takes the unsigned serialization and accounts for the signature itself.
  const unsigned = ethers.Transaction.from({
    type: 2,
    chainId: 10,
    nonce: tx.nonce,
    to: tx.to,
    data: tx.data,
    value: 0,
    gasLimit: Math.ceil((gasUsed * 5) / 4),
    maxPriorityFeePerGas: 1_000_000, // 0.001 gwei
    maxFeePerGas: 10_000_000, // 0.01 gwei
  }).unsignedSerialized;
  records.push({ op, actor, gasUsed, unsignedTx: unsigned });
  return receipt;
}

function median(sorted) {
  const n = sorted.length;
  return n % 2 ? sorted[(n - 1) / 2] : Math.round((sorted[n / 2 - 1] + sorted[n / 2]) / 2);
}

function summarise() {
  const ops = {};
  for (const r of records) (ops[r.op] ||= { actor: r.actor, gas: [], bytes: [], txs: [] }).gas.push(r.gasUsed);
  for (const r of records) {
    ops[r.op].bytes.push(ethers.dataLength(r.unsignedTx));
    ops[r.op].txs.push(r);
  }
  const out = {};
  for (const [op, v] of Object.entries(ops)) {
    const g = [...v.gas].sort((a, b) => a - b);
    const b = [...v.bytes].sort((a, b) => a - b);
    // representative transaction: the one whose gas is closest to the median (first such, in order)
    const med = median(g);
    const rep = v.txs.reduce((best, t) => (Math.abs(t.gasUsed - med) < Math.abs(best.gasUsed - med) ? t : best));
    out[op] = {
      actor: v.actor,
      count: g.length,
      gas: { min: g[0], median: med, max: g[g.length - 1], total: g.reduce((a, x) => a + x, 0) },
      unsignedTxBytes: { min: b[0], median: median(b), max: b[b.length - 1] },
      representativeTx: rep.unsignedTx,
    };
  }
  return out;
}

async function main() {
  const [governor, publisher, operator, reviewer, auditor, appellant] = await ethers.getSigners();
  await time.setNextBlockTimestamp(START - DAY);

  const schemaRegistry = await new ethers.ContractFactory(REGISTRY_ARTIFACT.abi, REGISTRY_ARTIFACT.bytecode, governor).deploy();
  const eas = await new ethers.ContractFactory(EAS_ARTIFACT.abi, EAS_ARTIFACT.bytecode, governor).deploy(await schemaRegistry.getAddress());
  const registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
  const anchor = await (await ethers.getContractFactory("MetricsAnchor")).deploy(await registry.getAddress());

  const name = "giga:XX:primary";
  await send("createScope", "governor", registry.connect(governor).createScope(name, 90 * 86400));
  const scope = await registry.scopeIdOf(governor.address, name);
  await send("setIssuer", "governor", registry.connect(governor).setIssuer(scope, operator.address, 1));
  await send("setIssuer", "governor", registry.connect(governor).setIssuer(scope, reviewer.address, 2));
  await send("setIssuer", "governor", registry.connect(governor).setIssuer(scope, auditor.address, 3));
  await send("setPublisher", "governor", anchor.connect(governor).setPublisher(scope, publisher.address, 7));

  const F = await ethers.getContractFactory("IssuerRoleResolver");
  const uid = {};
  for (const [schemaName, kind] of [["VPR.Deployment.v1", 0], ["VPR.IndependentTest.v1", 1]]) {
    const r = await F.deploy(await eas.getAddress(), await registry.getAddress(), kind);
    const def = EAS_SCHEMAS.schemas.find((s) => s.name === schemaName);
    await schemaRegistry.register(def.schema, await r.getAddress(), def.revocable);
    uid[schemaName] = schemaUid(ethers, def.schema, await r.getAddress(), def.revocable);
  }
  const coder = ethers.AbiCoder.defaultAbiCoder();
  const school = (i) => `giga-${String(i + 1).padStart(4, "0")}`;
  const req = (data) => ({ recipient: ethers.ZeroAddress, expirationTime: 0, revocable: true, refUID: ethers.ZeroHash, data, value: 0 });

  let version = 0;
  async function attestAll(at) {
    if (!W.attestEveryVersion) return;
    const deployments = [];
    for (let i = 0; i < W.schools; i++) {
      deployments.push(req(coder.encode(["string", "bytes32", "uint256", "bytes32", "uint64"],
        [school(i), scope, version, h(`zone:${version}`), at])));
    }
    await send("attest Deployment (multiAttest, all schools)", "operator",
      eas.connect(operator).multiAttest([{ schema: uid["VPR.Deployment.v1"], data: deployments }]));
    for (let i = 0; i < W.schools; i++) {
      const data = coder.encode(
        ["string", "bytes32", "uint256", "bool", "bool", "bool", "bool", "bytes32", "uint64", "uint64"],
        [school(i), scope, version, true, true, true, true, h(`report:${version}:${i}`), at, at + 45n * DAY]);
      await send("attest IndependentTest (one school)", "reviewer",
        eas.connect(reviewer).attest({ schema: uid["VPR.IndependentTest.v1"], data: req(data) }));
    }
  }

  async function publish(day, reason, resolves) {
    const at = START + BigInt(day) * DAY + 10n * 3600n + BigInt(version % 60) * 60n;
    await time.setNextBlockTimestamp(at);
    await send("publishPolicy", "governor", registry.connect(governor).publishPolicy(
      scope, h(`policy:${day}:${reason}`), day % 90 === 0 ? h(`restricted:${day}`) : ethers.ZeroHash,
      cid(`policy:${day}:${reason}`), reason, W.versionValidityDays * 86400, resolves || ethers.ZeroHash));
    version += 1;
    await attestAll(at);
  }

  // appeal schedule: filed on evenly spaced days; decided appealDecisionDays later
  const appealDays = Array.from({ length: W.appealsPerYear }, (_, i) => Math.floor(((i + 0.5) * W.days) / W.appealsPerYear));
  const correctionDays = Array.from({ length: W.correctionsPerYear }, (_, i) => Math.floor(((i + 1) * W.days) / (W.correctionsPerYear + 1)));
  const pending = []; // [decisionDay, appealId, index, documentHash]
  const rejectedDocs = [];

  for (let day = 0; day < W.days; day++) {
    const dayStart = START + BigInt(day) * DAY;
    // 01:00 UTC: the publisher anchors yesterday
    await time.setNextBlockTimestamp(dayStart + 3600n);
    const y = Number(dayStart / DAY) - 1;
    const weekday = new Date(Number((dayStart - DAY) * 1000n)).getUTCDay();
    if (W.closedWeekdays.includes(weekday)) {
      await send("markEmpty", "publisher", anchor.connect(publisher).markEmpty(scope, y));
    } else {
      await send("commitRoot", "publisher", anchor.connect(publisher).commitRoot(scope, y, h(`root:${y}`), cid(`release:${y}`)));
    }

    if (day === 0) await publish(day, 1);
    else if (day % W.renewalEveryDays === 0) await publish(day, 2);

    for (const [i, d] of appealDays.entries()) {
      if (d !== day) continue;
      await time.setNextBlockTimestamp(dayStart + 12n * 3600n);
      const doc = h(`appeal:${i}`);
      const r = await send("fileAppeal", "anyone", registry.connect(appellant).fileAppeal(scope, doc));
      const ev = r.logs.map((l) => { try { return registry.interface.parseLog(l); } catch { return null; } }).find((e) => e && e.name === "AppealFiled");
      pending.push([day + W.appealDecisionDays, ev.args.appealId, i, doc]);
    }
    for (const p of pending.filter((x) => x[0] === day)) {
      const [, appealId, i, doc] = p;
      if ((i + 1) % W.acceptEvery === 0) {
        await publish(day, 3, appealId);
      } else {
        await time.setNextBlockTimestamp(dayStart + 15n * 3600n + BigInt(i) * 60n);
        await send("rejectAppeal", "governor", registry.connect(governor).rejectAppeal(appealId, h(`decision:${i}`)));
        rejectedDocs.push([day, doc]);
      }
    }
    // a few rejected documents are filed again a week later (round 2)
    for (const [k, [d, doc]] of rejectedDocs.entries()) {
      if (k < W.resubmissions && d + 7 === day) {
        await time.setNextBlockTimestamp(dayStart + 16n * 3600n + BigInt(k) * 60n);
        await send("fileAppeal (round 2)", "anyone", registry.connect(appellant).fileAppeal(scope, doc));
      }
    }
    if (correctionDays.includes(day)) {
      await time.setNextBlockTimestamp(dayStart + 18n * 3600n);
      await send("correctRoot", "governor", anchor.connect(governor).correctRoot(scope, y, h(`corrected:${y}`), cid(`corrected:${y}`), h(`why:${y}`)));
    }
  }

  const result = {
    format: "vpr-bench-workload/1",
    environment: {
      evm: `Hardhat ${require("hardhat/package.json").version}, hardfork ${hre.network.config.hardfork || "default"}`,
      solc: "0.8.24, optimizer 200 runs, evmVersion cancun",
      eas: "EAS and SchemaRegistry from @ethereum-attestation-service/eas-contracts 1.9.0 (contracts v1.4.0)",
      note: "Execution gas of direct calls. Governor transactions are lower bounds: a Safe adds execTransaction and signature verification, not measured here.",
    },
    workload: { ...W, start: "2027-01-04T00:00:00Z", policyVersions: version },
    operations: summarise(),
  };

  if (process.env.BENCH_CHECK === "1") {
    const committed = JSON.parse(fs.readFileSync(OUT, "utf8"));
    const strip = (o) => JSON.stringify(Object.fromEntries(Object.entries(o.operations).map(([k, v]) => [k, [v.count, v.gas, v.unsignedTxBytes]])));
    if (strip(committed) !== strip(result)) {
      console.error("workload gas differs from the committed file; re-run without BENCH_CHECK and review the change");
      process.exit(1);
    }
    console.log("workload gas matches", path.relative(process.cwd(), OUT));
    return;
  }
  const previous = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT, "utf8")) : {};
  if (previous.l1) result.l1 = previous.l1; // keep the last L1 snapshot; bench-l1fee.js refreshes it
  fs.writeFileSync(OUT, JSON.stringify(result, null, 2) + "\n");
  for (const [op, v] of Object.entries(result.operations)) {
    console.log(`${op.padEnd(46)} ${String(v.count).padStart(5)}  median ${String(v.gas.median).padStart(8)}  bytes ${v.unsignedTxBytes.median}`);
  }
  console.log("wrote", path.relative(process.cwd(), OUT));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
