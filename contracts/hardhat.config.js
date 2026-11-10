require("@nomicfoundation/hardhat-toolbox");
const path = require("path");
const { subtask } = require("hardhat/config");
const { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } = require("hardhat/builtin-tasks/task-names");

// Offline mode: set OFFLINE_SOLC=1 to compile with the solc-js package from npm instead of
// downloading the native compiler (useful in CI sandboxes without access to binaries.soliditylang.org).
if (process.env.OFFLINE_SOLC === "1") {
  subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args, hre, runSuper) => {
    if (args.solcVersion === "0.8.24") {
      return {
        compilerPath: path.join(__dirname, "node_modules", "solc", "soljson.js"),
        isSolcJs: true,
        version: args.solcVersion,
        longVersion: "0.8.24+commit.e11b9ed9",
      };
    }
    return runSuper();
  });
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    // Pinned explicitly and identical in foundry.toml. Cancun is supported on OP Stack since Ecotone.
    settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "cancun" },
  },
  // REPORT_GAS=1 npx hardhat test writes a per-function gas table (used for docs/benchmarks/BENCHMARKS.md).
  gasReporter: {
    enabled: process.env.REPORT_GAS === "1",
    noColors: true,
    outputFile: process.env.GAS_REPORT_FILE || undefined,
  },
  paths: {
    sources: "./src",
    tests: "./test",
  },
  networks: {
    // Deployment targets for the pilot (see docs/ROADMAP.md). Set RPC URLs and keys via environment.
    opSepolia: {
      url: process.env.OP_SEPOLIA_RPC_URL || "",
      accounts: process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : [],
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "",
      accounts: process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : [],
    },
  },
};
