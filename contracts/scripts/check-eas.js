// SPDX-License-Identifier: AGPL-3.0-only
// Verifies the EAS schema bindings of a deployment manifest against the chain (VPR-070).
// Usage: MANIFEST=../deployments/<network>.json npx hardhat run --network <network> scripts/check-eas.js
// Exit code 0 if every schema is correctly bound, 1 otherwise.

const fs = require("fs");
const { ethers } = require("hardhat");
const { checkEasBindings } = require("./lib/eas-check");

async function main() {
  const file = process.env.MANIFEST;
  if (!file) throw new Error("set MANIFEST to the path of a vpr-manifest/1 file");
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const { chainId } = await ethers.provider.getNetwork();
  if (BigInt(manifest.chainId) !== chainId) throw new Error(`manifest chainId ${manifest.chainId} differs from the network (${chainId})`);

  const results = await checkEasBindings({ ethers, provider: ethers.provider, manifest });
  let failed = 0;
  for (const r of results) {
    if (r.problems.length === 0) {
      console.log(`ok    ${r.name}  ${r.uid}`);
    } else {
      failed++;
      for (const p of r.problems) console.log(`FAIL  ${r.name}: ${p}`);
    }
  }
  process.exitCode = failed ? 1 : 0;
}

main().catch((e) => {
  console.error(e.message || e);
  process.exitCode = 2;
});
