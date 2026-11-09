// SPDX-License-Identifier: AGPL-3.0-only
// On-chain half of the end-to-end demo. Runs on Hardhat's in-process network.
// Input: the JSON written by examples/e2e/prepare.py, passed in E2E_INPUT.
const fs = require("fs");
const { ethers } = require("hardhat");

const Role = { Operator: 1, Reviewer: 2 };

function check(cond, msg) {
  if (!cond) {
    console.error(`FAIL  ${msg}`);
    process.exit(1);
  }
  console.log(`ok    ${msg}`);
}

async function main() {
  const d = JSON.parse(fs.readFileSync(process.env.E2E_INPUT, "utf8"));
  // In a real deployment the governor is a Safe multisig; here it is a single local account.
  const [governor, operator, reviewer, teacher, stranger] = await ethers.getSigners();
  const day = 24n * 3600n;

  const registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
  const anchor = await (await ethers.getContractFactory("MetricsAnchor")).deploy(await registry.getAddress());
  console.log(`1. deployed registry ${await registry.getAddress()} and anchor ${await anchor.getAddress()}`);

  check(ethers.id(d.scope) === d.scopeId, "scopeId computed off-chain equals keccak256(scope)");
  await (await registry.connect(governor).createScope(d.scopeId, governor.address, 90n * day)).wait();
  await (await registry.connect(governor).setIssuer(d.scopeId, operator.address, Role.Operator)).wait();
  await (await registry.connect(governor).setIssuer(d.scopeId, reviewer.address, Role.Reviewer)).wait();
  await (await anchor.connect(governor).setPublisher(d.scopeId, operator.address)).wait();
  console.log(`2. governor created ${d.scope}, registered operator and reviewer roles, appointed the publisher`);
  check(
    (await registry.issuerRole(d.scopeId, operator.address)) !== (await registry.issuerRole(d.scopeId, reviewer.address)),
    "operator and reviewer hold different roles"
  );
  let claimRejected = false;
  try {
    await anchor.connect(stranger).setPublisher(d.scopeId, stranger.address);
  } catch (e) {
    claimRejected = true;
  }
  check(claimRejected, "a stranger cannot claim the scope's publisher");

  await (
    await registry
      .connect(governor)
      .publishPolicy(d.scopeId, d.contentHash, ethers.ZeroHash, d.policyUri, d.reasonCode, BigInt(d.validDays) * day, ethers.ZeroHash)
  ).wait();
  console.log(`3. governor published policy v1 (valid ${d.validDays} days, reason ${d.reasonCode})`);
  const [version, current, inForce] = await registry.currentPolicy(d.scopeId);
  check(version === 1n && inForce, "policy v1 published and in force");
  check(current.contentHash === d.contentHash, "on-chain contentHash equals the hash of the published document");

  await (await registry.connect(teacher).fileAppeal(d.scopeId, d.appealDocumentHash)).wait();
  const appealId = await registry.appealIdOf(d.scopeId, d.appealDocumentHash, 1);
  check((await registry.appeals(appealId)).documentHash === d.appealDocumentHash, "appeal recorded as a document hash only");
  console.log("4. a teacher filed an appeal (in production through the relayer; no wallet needed)");

  console.log("5. aggregation and suppression happened off-chain; only the root goes on-chain");
  await (await anchor.connect(operator).commitRoot(d.scopeId, d.dayNumber, d.root, d.datasetUri)).wait();
  console.log(`6. operator anchored the root for ${d.day}`);

  console.log(`7. verifying rows against the anchored root (k = ${d.k})`);
  const r = d.row;
  const t = d.tamperedRow;
  check(
    await anchor.verifyRow(d.scopeId, d.dayNumber, r.school_id, r.category, r.count, d.proof),
    `published row verifies: ${JSON.stringify(r)}`
  );
  check(
    !(await anchor.verifyRow(d.scopeId, d.dayNumber, t.school_id, t.category, t.count, d.proof)),
    `tampered row is rejected: ${JSON.stringify(t)}`
  );
  check(
    !(await anchor.verifyRow(d.scopeId, d.dayNumber + 1, r.school_id, r.category, r.count, d.proof)),
    "the same row is rejected for another day"
  );

  let rewriteRejected = false;
  try {
    await anchor.connect(operator).commitRoot(d.scopeId, d.dayNumber, ethers.id("other"), d.datasetUri);
  } catch (e) {
    rewriteRejected = true;
  }
  check(rewriteRejected, "an anchored day cannot be rewritten");
  console.log("\nEnd-to-end demo passed.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
