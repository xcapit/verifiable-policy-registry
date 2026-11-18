// SPDX-License-Identifier: AGPL-3.0-only
// Verifies that each scope's governor is the Safe the deployment manifest declares, with the declared threshold.
// Usage: MANIFEST=../deployments/<network>.json npx hardhat run --network <network> scripts/check-governor.js
// Exit code 0 if every scope passes, 1 if any check fails, 2 on error. Read-only.

const fs = require("fs");
const { ethers } = require("hardhat");
const { checkGovernors } = require("./lib/governor-check");

async function main() {
  const file = process.env.MANIFEST;
  if (!file) throw new Error("set MANIFEST to the path of a vpr-manifest/1 file");
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const { chainId } = await ethers.provider.getNetwork();
  if (BigInt(manifest.chainId) !== chainId) throw new Error(`manifest chainId ${manifest.chainId} differs from the network (${chainId})`);

  // Read every value at the block the manifest's finality tag resolves to now, so that all reads agree.
  const tag = manifest.finality || "finalized";
  const block = await ethers.provider.getBlock(tag);
  if (!block) throw new Error(`the node returned no block for tag ${tag}`);
  console.log(`read at block ${block.number} (${tag})`);
  const results = await checkGovernors({ ethers, provider: ethers.provider, manifest, blockTag: block.number });
  let failed = 0;
  for (const r of results) {
    for (const i of r.info) console.log(`info  ${r.name}: ${i}`);
    if (r.problems.length === 0) {
      console.log(`ok    ${r.name}  governor ${r.governor}`);
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
