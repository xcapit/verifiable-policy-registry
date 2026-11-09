// SPDX-License-Identifier: AGPL-3.0-only
// On-chain half of the end-to-end demo. Runs on Hardhat's in-process network.
// Input: the JSON written by examples/e2e/prepare.py, passed in E2E_INPUT.
const fs = require("fs");
const { ethers } = require("hardhat");

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
  const [governor, operator, teacher] = await ethers.getSigners();

  const Registry = await ethers.getContractFactory("VerifiablePolicyRegistry");
  const registry = await Registry.deploy();
  const Anchor = await ethers.getContractFactory("MetricsAnchor");
  const anchor = await Anchor.deploy();
  console.log(`1. deployed registry ${await registry.getAddress()} and anchor ${await anchor.getAddress()}`);

  check(ethers.id(d.scope) === d.scopeId, "scopeId computed off-chain equals keccak256(scope)");
  const day = 24n * 3600n;
  await (await registry.createScope(d.scopeId, governor.address, 90n * day)).wait();
  await (await anchor.configure(d.scopeId, governor.address, operator.address)).wait();
  console.log(`2. created scope ${d.scope}; anchor admin = governor, publisher = operator`);

  await (
    await registry
      .connect(governor)
      .publishPolicy(d.scopeId, d.contentHash, ethers.ZeroHash, d.policyUri, d.reasonCode, BigInt(d.validDays) * day, ethers.ZeroHash)
  ).wait();
  console.log(`3. governor published policy v1 (valid ${d.validDays} days, reason ${d.reasonCode})`);
  const [version, current, inForce] = await registry.currentPolicy(d.scopeId);
  check(version === 1n && inForce, "policy v1 published and in force");
  check(current.contentHash === d.contentHash, "on-chain contentHash equals the hash of the published document");

  await (await registry.connect(teacher).fileAppeal(d.scopeId, "ipfs://example-appeal")).wait();
  console.log("4. a teacher filed an appeal (no wallet needed in production: relayer)");

  await (await anchor.connect(operator).commitRoot(d.scopeId, d.dayNumber, d.root, d.datasetUri)).wait();
  console.log(`5. aggregation and suppression happened off-chain; only the root goes on-chain`);
  console.log(`6. operator anchored the root for ${d.day}`);

  console.log(`7. verifying rows against the anchored root (k = ${d.k}, ${d.suppressedCells} cells suppressed off-chain)`);
  check(await anchor.verifyLeaf(d.scopeId, d.dayNumber, d.leaf, d.proof), `published row verifies: ${JSON.stringify(d.row)}`);
  check(
    !(await anchor.verifyLeaf(d.scopeId, d.dayNumber, d.tamperedLeaf, d.proof)),
    `tampered row is rejected: ${JSON.stringify(d.tamperedRow)}`
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
