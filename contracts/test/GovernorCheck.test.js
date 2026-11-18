// Governor check against a real Safe (scripts/lib/governor-check.js).
// The Safe singleton (SafeL2 and Safe), SafeProxyFactory and an example guard are deployed from the compiled
// artifacts published in @safe-global/safe-contracts, pinned to exactly 1.4.1. That package is used because it
// is the official release of Safe 1.4.1, the version deployed canonically on OP Mainnet; the newer
// @safe-global/safe-smart-account is published on npm only as 1.5.0. The runtime code hashes of the Safe,
// SafeL2 and SafeProxyFactory artifacts equal the codeHash that @safe-global/safe-deployments records for the
// canonical 1.4.1 deployments (asserted below). The package declares a peer dependency on ethers 5.4.0, which
// package.json overrides to the ethers 6 the toolbox uses: only the JSON artifacts are read, never its scripts.
const fs = require("fs");
const path = require("path");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { checkGovernors, enabledModules, parseThreshold, versionAtLeast, safeSlots, SENTINEL } = require("../scripts/lib/governor-check");

const ARTIFACTS = "@safe-global/safe-contracts/build/artifacts/contracts";
const SAFE = require(`${ARTIFACTS}/Safe.sol/Safe.json`);
const SAFE_L2 = require(`${ARTIFACTS}/SafeL2.sol/SafeL2.json`);
const FACTORY = require(`${ARTIFACTS}/proxies/SafeProxyFactory.sol/SafeProxyFactory.json`);
const PROXY = require(`${ARTIFACTS}/proxies/SafeProxy.sol/SafeProxy.json`);
const GUARD = require(`${ARTIFACTS}/examples/guards/DebugTransactionGuard.sol/DebugTransactionGuard.json`);

// codeHash of the canonical v1.4.1 deployments in @safe-global/safe-deployments 1.37.67 (src/assets/v1.4.1/*.json).
const CANONICAL_CODE_HASH = {
  safe: "0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4",
  safeL2: "0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff",
  factory: "0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317",
};
const PROXY_CODE_HASH = ethers.keccak256(PROXY.deployedBytecode);
const NAME = "giga:XX:primary";

describe("Governor check against a real Safe 1.4.1", function () {
  let deployer, owners, other, outsider;
  let registry, singleton, plainSingleton, factory, safe, safeAddress, scopeId, manifest;

  // Executes a call from the Safe with `count` owner approvals (approveHash, then a pre-validated signature
  // per owner, sorted by owner address as Safe requires). The last owner submits and needs no approveHash.
  async function execFromSafe(to, data, count = 2) {
    const nonce = await safe.nonce();
    const args = [to, 0, data, 0, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress];
    const hash = await safe.getTransactionHash(...args, nonce);
    const signers = owners.slice(0, count);
    const submitter = signers[signers.length - 1];
    for (const s of signers.slice(0, -1)) await safe.connect(s).approveHash(hash);
    const sorted = [...signers].sort((a, b) => (BigInt(a.address) < BigInt(b.address) ? -1 : 1));
    const signatures = ethers.concat(sorted.map((s) => ethers.concat([ethers.zeroPadValue(s.address, 32), ethers.ZeroHash, "0x01"])));
    const receipt = await (await safe.connect(submitter).execTransaction(...args, signatures)).wait();
    const failed = receipt.logs.map((l) => safe.interface.parseLog(l)).find((e) => e && e.name === "ExecutionFailure");
    expect(failed, "Safe transaction failed").to.equal(undefined);
  }

  async function check() {
    return checkGovernors({ ethers, provider: ethers.provider, manifest });
  }
  async function problems() {
    const results = await check();
    expect(results).to.have.length(1);
    return results[0].problems;
  }

  // hardhat_setCode changes accounts that later tests reuse, so every test runs from a snapshot.
  let snapshot;
  afterEach(async function () {
    await network.provider.send("evm_revert", [snapshot]);
  });

  beforeEach(async function () {
    snapshot = await network.provider.send("evm_snapshot", []);
    let a, b, c;
    [deployer, a, b, c, other, outsider] = await ethers.getSigners();
    owners = [a, b, c];
    singleton = await new ethers.ContractFactory(SAFE_L2.abi, SAFE_L2.bytecode, deployer).deploy();
    plainSingleton = await new ethers.ContractFactory(SAFE.abi, SAFE.bytecode, deployer).deploy();
    factory = await new ethers.ContractFactory(FACTORY.abi, FACTORY.bytecode, deployer).deploy();

    const setup = singleton.interface.encodeFunctionData("setup", [
      owners.map((o) => o.address),
      2,
      ethers.ZeroAddress,
      "0x",
      ethers.ZeroAddress,
      ethers.ZeroAddress,
      0,
      ethers.ZeroAddress,
    ]);
    safeAddress = await factory.createProxyWithNonce.staticCall(await singleton.getAddress(), setup, 0);
    await factory.createProxyWithNonce(await singleton.getAddress(), setup, 0);
    safe = new ethers.Contract(safeAddress, SAFE_L2.abi, deployer);

    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await execFromSafe(await registry.getAddress(), registry.interface.encodeFunctionData("createScope", [NAME, 90 * 86400]));
    scopeId = await registry.scopeIdOf(safeAddress, NAME);
    expect((await registry.scopes(scopeId)).governor).to.equal(safeAddress);

    manifest = {
      chainId: 31337,
      contracts: { registry: await registry.getAddress() },
      governorSafe: { singletons: [await singleton.getAddress(), await plainSingleton.getAddress()], proxyCodeHashes: [PROXY_CODE_HASH] },
      scopes: [{ name: NAME, scopeId, governor: safeAddress, governorThreshold: "2-of-3" }],
    };
  });

  it("uses artifacts identical to the canonical Safe 1.4.1 deployments, and the factory deploys SafeProxy", async function () {
    expect(ethers.keccak256(await ethers.provider.getCode(await plainSingleton.getAddress()))).to.equal(CANONICAL_CODE_HASH.safe);
    expect(ethers.keccak256(await ethers.provider.getCode(await singleton.getAddress()))).to.equal(CANONICAL_CODE_HASH.safeL2);
    expect(ethers.keccak256(await ethers.provider.getCode(await factory.getAddress()))).to.equal(CANONICAL_CODE_HASH.factory);
    expect(ethers.keccak256(await ethers.provider.getCode(safeAddress))).to.equal(PROXY_CODE_HASH);
    expect(await safe.VERSION()).to.equal("1.4.1");
    // the synthetic example manifest declares the same proxy code hash
    const example = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "deployments", "example.local.json.example"), "utf8"));
    expect(example.governorSafe.proxyCodeHashes).to.deep.equal([PROXY_CODE_HASH]);
  });

  it("passes when the governor is the declared 2-of-3 Safe", async function () {
    const [r] = await check();
    expect(r.problems).to.deep.equal([]);
    expect(r.governor).to.equal(safeAddress);
    expect(r.info).to.include(`Safe 1.4.1, singleton ${await singleton.getAddress()}`);
  });

  it("fails when the Safe threshold differs from the declared one", async function () {
    await execFromSafe(safeAddress, safe.interface.encodeFunctionData("changeThreshold", [1]));
    expect(await safe.getThreshold()).to.equal(1n);
    expect(await problems()).to.deep.equal(["Safe is 1-of-3, manifest declares 2-of-3"]);
  });

  it("fails when the declared threshold is malformed or missing", async function () {
    manifest.scopes[0].governorThreshold = "3-of-2";
    expect(await problems()).to.deep.equal(["governorThreshold 3-of-2 is not m-of-n with 1 <= m <= n"]);
    delete manifest.scopes[0].governorThreshold;
    expect(await problems()).to.deep.equal(["manifest lacks governorThreshold"]);
  });

  it("fails when the governor is an EOA", async function () {
    await registry.connect(other).createScope(NAME, 90 * 86400);
    const eoaScope = await registry.scopeIdOf(other.address, NAME);
    manifest.scopes[0] = { ...manifest.scopes[0], scopeId: eoaScope, governor: other.address };
    expect(await problems()).to.deep.equal(["governor has no code (an EOA, or a contract not yet deployed), so it is not a Safe"]);
  });

  it("fails when the governor is an EIP-7702 delegated EOA, without calling it", async function () {
    await registry.connect(other).createScope(NAME, 90 * 86400);
    const eoaScope = await registry.scopeIdOf(other.address, NAME);
    // Delegation designator 0xef0100 || address, here delegating to the Safe proxy's own code location.
    const designator = ethers.concat(["0xef0100", safeAddress]);
    await network.provider.send("hardhat_setCode", [other.address, designator]);
    expect(await ethers.provider.getCode(other.address)).to.equal(designator.toLowerCase());
    manifest.scopes[0] = { ...manifest.scopes[0], scopeId: eoaScope, governor: other.address };
    expect(await problems()).to.deep.equal([`governor is an EIP-7702 delegated EOA (delegate ${safeAddress}), not a Safe`]);
  });

  it("fails when the governor's code is not a declared SafeProxy", async function () {
    await registry.connect(other).createScope(NAME, 90 * 86400);
    const eoaScope = await registry.scopeIdOf(other.address, NAME);
    // A contract that answers like a Safe (the singleton's own code) but is not a proxy.
    await network.provider.send("hardhat_setCode", [other.address, SAFE_L2.deployedBytecode]);
    manifest.scopes[0] = { ...manifest.scopes[0], scopeId: eoaScope, governor: other.address };
    const hash = ethers.keccak256(SAFE_L2.deployedBytecode);
    expect(await problems()).to.deep.equal([`governor code hash ${hash} is not a declared SafeProxy code hash`]);
  });

  it("fails when an undeclared module is enabled, and accepts a declared one", async function () {
    await execFromSafe(safeAddress, safe.interface.encodeFunctionData("enableModule", [outsider.address]));
    expect(await safe.isModuleEnabled(outsider.address)).to.equal(true);
    expect(await problems()).to.deep.equal([
      `module ${outsider.address} is enabled and not declared; a module executes transactions without the owners' signatures`,
    ]);
    manifest.scopes[0].governorModules = [outsider.address.toLowerCase()];
    const [r] = await check();
    expect(r.problems).to.deep.equal([]);
    expect(r.info).to.include(`module ${outsider.address} enabled (declared in the manifest)`);
  });

  it("reads every page of enabled modules", async function () {
    const modules = [];
    for (let i = 0; i < 52; i++) modules.push(ethers.getAddress(ethers.zeroPadValue(ethers.toBeHex(0x1000 + i), 20)));
    for (const m of modules) await execFromSafe(safeAddress, safe.interface.encodeFunctionData("enableModule", [m]));
    manifest.scopes[0].governorModules = modules.slice(1);
    expect(await problems()).to.deep.equal([
      `module ${modules[0]} is enabled and not declared; a module executes transactions without the owners' signatures`,
    ]);
  });

  it("fails when the singleton is not declared", async function () {
    manifest.governorSafe.singletons = [await plainSingleton.getAddress()];
    expect(await problems()).to.deep.equal([`Safe singleton ${await singleton.getAddress()} is not one of the declared singletons`]);
  });

  it("fails closed when the manifest does not declare the Safe code", async function () {
    delete manifest.governorSafe;
    expect(await problems()).to.deep.equal(["manifest lacks governorSafe.singletons", "manifest lacks governorSafe.proxyCodeHashes"]);
  });

  it("fails when the scope or the registry does not exist", async function () {
    manifest.scopes[0].scopeId = ethers.id("no such scope");
    expect(await problems()).to.deep.equal(["scope does not exist in the registry"]);
    manifest.contracts.registry = outsider.address;
    expect(await problems()).to.deep.equal(["no contract at contracts.registry"]);
    manifest.contracts.registry = await factory.getAddress();
    expect(await problems()).to.deep.equal(["contracts.registry does not answer scopes(bytes32); not a VerifiablePolicyRegistry"]);
  });

  it("reports a pending handover, then fails when the registry governor differs from the manifest", async function () {
    await execFromSafe(await registry.getAddress(), registry.interface.encodeFunctionData("proposeGovernor", [scopeId, other.address]));
    let [r] = await check();
    expect(r.problems).to.deep.equal([]);
    expect(r.info).to.include(`governor handover to ${other.address} is pending`);

    await registry.connect(other).acceptGovernor(scopeId);
    expect((await registry.scopes(scopeId)).governor).to.equal(other.address);
    [r] = await check();
    expect(r.governor).to.equal(other.address);
    // the Safe checks apply to the on-chain governor, here an EOA
    expect(r.problems).to.deep.equal([
      `registry governor ${other.address} differs from the manifest governor ${safeAddress}`,
      "governor has no code (an EOA, or a contract not yet deployed), so it is not a Safe",
    ]);
  });

  it("reports a transaction guard as information", async function () {
    const guard = await new ethers.ContractFactory(GUARD.abi, GUARD.bytecode, deployer).deploy();
    await execFromSafe(safeAddress, safe.interface.encodeFunctionData("setGuard", [await guard.getAddress()]));
    const slot = await ethers.provider.getStorage(safeAddress, safeSlots(ethers).guard);
    expect(ethers.getAddress(ethers.dataSlice(slot, 12))).to.equal(await guard.getAddress());
    const [r] = await check();
    expect(r.problems).to.deep.equal([]);
    expect(r.info).to.include(`transaction guard ${await guard.getAddress()} is set`);
  });

  it("reads at the given block", async function () {
    const before = await ethers.provider.getBlockNumber();
    await execFromSafe(safeAddress, safe.interface.encodeFunctionData("changeThreshold", [1]));
    const [r] = await checkGovernors({ ethers, provider: ethers.provider, manifest, blockTag: before });
    expect(r.problems).to.deep.equal([]);
    expect(await problems()).to.deep.equal(["Safe is 1-of-3, manifest declares 2-of-3"]);
  });

  it("reads module pages with both the 1.3.0 and the 1.4.x meaning of next", async function () {
    // Stubs that follow ModuleManager.getModulesPaginated of each version over the same list of 7 modules.
    const list = Array.from({ length: 7 }, (_, i) => ethers.getAddress(ethers.zeroPadValue(ethers.toBeHex(0x2000 + i), 20)));
    const succ = (a) => (same(a, SENTINEL) ? list[0] : list[list.findIndex((m) => same(m, a)) + 1] || SENTINEL);
    const same = (a, b) => a.toLowerCase() === b.toLowerCase();
    const page = (start, size) => {
      const array = [];
      let cur = succ(start);
      while (!same(cur, SENTINEL) && array.length < size) {
        array.push(cur);
        cur = succ(cur);
      }
      return { array, firstNotInPage: cur };
    };
    const v130 = { getModulesPaginated: async (start, size) => [page(start, 3).array, page(start, 3).firstNotInPage] };
    const v141 = {
      getModulesPaginated: async (start, size) => {
        const { array, firstNotInPage } = page(start, 3);
        return [array, same(firstNotInPage, SENTINEL) ? SENTINEL : array[array.length - 1]];
      },
    };
    expect((await enabledModules(v130, {})).modules).to.deep.equal(list);
    expect((await enabledModules(v141, {})).modules).to.deep.equal(list);
  });

  it("parses thresholds and versions", function () {
    expect(parseThreshold("2-of-3")).to.deep.equal({ m: 2, n: 3 });
    expect(parseThreshold("0-of-3")).to.equal(null);
    expect(parseThreshold("2of3")).to.equal(null);
    expect(versionAtLeast("1.3.0")).to.equal(true);
    expect(versionAtLeast("1.4.1")).to.equal(true);
    expect(versionAtLeast("2.0.0")).to.equal(true);
    expect(versionAtLeast("1.2.0")).to.equal(false);
    expect(versionAtLeast("0.9.9")).to.equal(false);
    expect(versionAtLeast("unknown")).to.equal(false);
  });
});
