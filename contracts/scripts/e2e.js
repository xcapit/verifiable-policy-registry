// SPDX-License-Identifier: AGPL-3.0-only
// On-chain half of the end-to-end demonstrator. Runs on Hardhat's in-process network (chain id 31337),
// with synthetic data. Input: E2E_INPUT (e2e.json from examples/e2e/prepare.py).
// Output: E2E_MANIFEST (evidence manifest), merging the off-chain evidence in E2E_OFFCHAIN.
const fs = require("fs");
const hre = require("hardhat");
const { ethers } = hre;
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const Role = { Operator: 1, Reviewer: 2 };
const DAY = 24n * 3600n;
const stages = [];
const gas = {};

function check(cond, msg) {
  if (!cond) {
    console.error(`FAIL  ${msg}`);
    stages.push({ stage: msg, status: "failed" });
    writeManifest(false);
    process.exit(1);
  }
  console.log(`ok    ${msg}`);
  stages.push({ stage: msg, status: "passed" });
}

async function send(label, txPromise) {
  const receipt = await (await txPromise).wait();
  gas[label] = Number(receipt.gasUsed);
  return receipt;
}

// True only if the call reverts with the named custom error (not for any other failure).
async function reverts(promise, errorName) {
  try {
    await promise;
    return false;
  } catch (e) {
    const text = `${e.message || ""} ${e.errorName || ""} ${JSON.stringify(e.revert || {})}`;
    return text.includes(errorName);
  }
}

let manifestBase = {};
function writeManifest(passed) {
  if (!process.env.E2E_MANIFEST) return;
  const offchain = process.env.E2E_OFFCHAIN && fs.existsSync(process.env.E2E_OFFCHAIN) ? JSON.parse(fs.readFileSync(process.env.E2E_OFFCHAIN, "utf8")) : {};
  const manifest = {
    manifestFormat: "vpr-demo-evidence/1",
    result: passed ? "passed" : "failed",
    sourceCommit: process.env.E2E_COMMIT || "unknown",
    environment: {
      network: "hardhat in-process (local, ephemeral)",
      chainId: 31337,
      node: process.version,
      hardhat: require("hardhat/package.json").version,
      solc: hre.config.solidity.compilers ? hre.config.solidity.compilers[0].version : hre.config.solidity.version,
      python: offchain.python,
      vprTools: offchain.vprToolsVersion,
      toolkitApi: offchain.toolkitApi,
      datasetFormat: offchain.datasetFormat,
    },
    ...manifestBase,
    offchainStages: offchain.stages || [],
    onchainStages: stages,
    gasUsed: gas,
    notImplemented: [
      { stage: "dns-resolution", note: "No resolver runs in the demo; the compiled zone is evaluated (vpr evaluate). A pinned resolver container is planned (VPR-055)." },
      { stage: "zk-proof", note: "Zero-knowledge proof of aggregation is Designed, not implemented. Specification: docs/security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md; milestone M4 (docs/ROADMAP.md)." },
    ],
    limitations: [
      "Synthetic data only; local ephemeral chain; addresses are meaningful only for this run.",
      "The anchored root proves the release was not altered after anchoring; it does not prove the events were complete or truthful.",
      "Gas figures are from the Hardhat EVM and are indicative of OP Mainnet execution gas only; L1 data fees are not included.",
    ],
  };
  fs.writeFileSync(process.env.E2E_MANIFEST, JSON.stringify(manifest, null, 2));
}

async function main() {
  const d = JSON.parse(fs.readFileSync(process.env.E2E_INPUT, "utf8"));
  // In a real deployment the governor is a Safe multisig; here it is a single local account.
  const [governor, operator, reviewer, teacher, stranger] = await ethers.getSigners();

  const registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
  const anchor = await (await ethers.getContractFactory("MetricsAnchor")).deploy(await registry.getAddress());
  console.log(`1. deployed registry ${await registry.getAddress()} and anchor ${await anchor.getAddress()}`);
  manifestBase.contracts = { registry: await registry.getAddress(), anchor: await anchor.getAddress() };

  await send("createScope", registry.connect(governor).createScope(d.scope, 90n * DAY));
  d.scopeId = await registry.scopeIdOf(governor.address, d.scope);
  const expectedId = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "string"], [governor.address, d.scope]));
  check(d.scopeId === expectedId, "scope id is derived on-chain from the governor and the scope name");
  await registry.connect(stranger).createScope(d.scope, 90n * DAY);
  check(
    (await registry.scopes(d.scopeId)).governor === governor.address,
    "the same scope name created by another address does not affect this scope (no front-running)"
  );
  await send("setIssuer", registry.connect(governor).setIssuer(d.scopeId, operator.address, Role.Operator));
  await registry.connect(governor).setIssuer(d.scopeId, reviewer.address, Role.Reviewer);
  // the demonstrator anchors fixed historical synthetic data, so it disables the back-fill bound
  const NO_LAG_LIMIT = await anchor.NO_LAG_LIMIT();
  await send("setPublisher", anchor.connect(governor).setPublisher(d.scopeId, operator.address, NO_LAG_LIMIT));
  console.log(`2. governor created ${d.scope}, registered operator and reviewer roles, appointed the publisher`);
  check(await reverts(anchor.connect(stranger).setPublisher(d.scopeId, stranger.address, 1), "NotGovernor"), "a stranger cannot claim the scope's publisher (NotGovernor)");

  await send(
    "publishPolicy",
    registry.connect(governor).publishPolicy(d.scopeId, d.contentHash, ethers.ZeroHash, d.policyUri, d.reasonCode, BigInt(d.validDays) * DAY, ethers.ZeroHash)
  );
  console.log(`3. governor published policy v${d.policyVersion} (valid ${d.validDays} days, reason ${d.reasonCode})`);
  const [version, current, inForce] = await registry.currentPolicy(d.scopeId);
  check(version === 1n && inForce, "policy v1 published and in force");
  check(current.contentHash === d.contentHash, "on-chain contentHash equals the hash of the published document");
  check(current.contentHash !== d.tamperedDocumentHash, "a modified policy document does not match the on-chain contentHash");
  manifestBase.policy = { scope: d.scope, scopeId: d.scopeId, governor: governor.address, version: d.policyVersion, contentHash: d.contentHash, zoneHash: d.zoneHash };

  const resolver = await (await ethers.getContractFactory("IssuerRoleResolver")).deploy(stranger.address, await registry.getAddress(), 1 /* SchemaKind.IndependentTest */);
  const testData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["string", "bytes32", "uint256", "bool", "bool", "bool", "bool", "bytes32", "uint64", "uint64"],
    ["giga-0001", d.scopeId, 1, true, true, true, true, ethers.id("report"), 1, 2]
  );
  const att = (attester) => ({ uid: ethers.ZeroHash, schema: ethers.ZeroHash, time: 0, expirationTime: 0, revocationTime: 0, refUID: ethers.ZeroHash, recipient: ethers.ZeroAddress, attester, revocable: true, data: testData });
  check(await resolver.connect(stranger).attest.staticCall(att(reviewer.address)), "EAS resolver accepts a test attestation from the reviewer");
  check(!(await resolver.connect(stranger).attest.staticCall(att(operator.address))), "EAS resolver rejects a test attestation from the operator");

  await send("fileAppeal", registry.connect(teacher).fileAppeal(d.scopeId, d.appealDocumentHash));
  const appealId = await registry.appealIdOf(d.scopeId, d.appealDocumentHash, 1);
  check((await registry.appeals(appealId)).documentHash === d.appealDocumentHash, "appeal recorded as a document hash only");
  await send("rejectAppeal", registry.connect(governor).rejectAppeal(appealId, ethers.id("reasoned decision (synthetic)")));
  check((await registry.appeals(appealId)).status === 3n, "governor rejected the appeal with a reasoned-decision hash");
  await registry.connect(teacher).fileAppeal(d.scopeId, d.appealDocumentHash);
  check((await registry.appeals(await registry.appealIdOf(d.scopeId, d.appealDocumentHash, 2))).status === 1n, "the rejected appeal was resubmitted in round 2");
  console.log("4. appeal filed, rejected with reasons and resubmitted");

  console.log("5. aggregation and suppression happened off-chain; only the root goes on-chain");
  await send("commitRoot", anchor.connect(operator).commitRoot(d.scopeId, d.dayNumber, d.root, d.datasetUri));
  console.log(`6. operator anchored the root for ${d.day}`);
  const stored = await anchor.getCommitment(d.scopeId, d.dayNumber);
  check(stored.root === d.root, "root read back from chain state equals the locally computed root");
  manifestBase.school = { day: d.day, dayNumber: d.dayNumber, root: d.root, proofFixture: "e2e.json#/proof (row 0)" };

  console.log(`7. verifying rows against the anchored root (k = ${d.k})`);
  const r = d.row;
  const t = d.tamperedRow;
  check(await anchor.verifyRow(d.scopeId, d.dayNumber, r.school_id, r.category, r.count, d.proof), "published row verifies on-chain");
  check(!(await anchor.verifyRow(d.scopeId, d.dayNumber, t.school_id, t.category, t.count, d.proof)), "tampered row (count + 1) is rejected");
  check(!(await anchor.verifyRow(d.scopeId, d.dayNumber + 1, r.school_id, r.category, r.count, d.proof)), "the same row is rejected for another day");
  // a different root anchored for another day: the published row must not verify against it
  const otherDay = d.dayNumber + 2;
  await anchor.connect(operator).commitRoot(d.scopeId, otherDay, ethers.id("unrelated root"), d.datasetUri);
  check(!(await anchor.verifyRow(d.scopeId, otherDay, r.school_id, r.category, r.count, d.proof)), "the published row does not verify against a different anchored root");
  gas.verifyRow_estimate = Number(await anchor.verifyRow.estimateGas(d.scopeId, d.dayNumber, r.school_id, r.category, r.count, d.proof));
  const currentDay = Number(await anchor.today());
  check(
    await reverts(anchor.connect(operator).commitRoot(d.scopeId, currentDay, d.root, d.datasetUri), "DayNotClosed"),
    "the current UTC day, still accumulating, cannot be anchored (DayNotClosed)"
  );
  await send("markEmpty", anchor.connect(operator).markEmpty(d.scopeId, d.dayNumber - 1));
  check((await anchor.getCommitment(d.scopeId, d.dayNumber - 1)).empty, "a day with nothing publishable is marked empty, so the gap is not ambiguous");
  await send("correctRoot", anchor.connect(governor).correctRoot(d.scopeId, otherDay, d.root, d.datasetUri, ethers.id("correction note")));
  check((await anchor.getCommitment(d.scopeId, otherDay)).revision === 1n, "the governor corrected an anchored root, with a reason, and the revision is counted");
  check(await reverts(anchor.connect(operator).commitRoot(d.scopeId, d.dayNumber, ethers.id("other"), d.datasetUri), "DayAlreadyCommitted"), "an anchored day cannot be rewritten (DayAlreadyCommitted)");

  if (d.service) {
    const s = d.service;
    await registry.connect(governor).createScope(s.scope, 90n * DAY);
    s.scopeId = await registry.scopeIdOf(governor.address, s.scope);
    await anchor.connect(governor).setPublisher(s.scopeId, operator.address, NO_LAG_LIMIT);
    await anchor.connect(operator).commitRoot(s.scopeId, s.dayNumber, s.root, "ipfs://example-service-dataset");
    check(
      await anchor.verifyRow(s.scopeId, s.dayNumber, s.row.unit_id, s.row.category, s.row.count, s.proof),
      "second use case (public-service release) verifies with the same verifier"
    );
    manifestBase.publicService = { scope: s.scope, day: s.day, root: s.root };
    console.log("8. public-service release anchored and verified with the same contract");
  }

  await time.increase(Number(BigInt(d.validDays) * DAY) + 1);
  const [, , stillInForce] = await registry.currentPolicy(d.scopeId);
  check(!stillInForce, `policy v1 is reported as not in force after ${d.validDays} days (mandatory expiry)`);
  console.log("9. expiry: the policy lapses unless the governor signs it again");

  console.log("10. ZK proof of aggregation: NOT IMPLEMENTED (Designed; see docs/security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md, roadmap M4)");
  writeManifest(true);
  console.log("\nEnd-to-end demo passed.");
}

main().catch((e) => {
  console.error(e);
  writeManifest(false);
  process.exit(1);
});
