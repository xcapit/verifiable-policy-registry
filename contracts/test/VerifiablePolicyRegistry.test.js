const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const SCOPE = ethers.id("giga:XX:primary");
const DAY = 24 * 60 * 60;
const MAX_VALIDITY = 90 * DAY;
const REASON_INITIAL = 1;
const REASON_APPEAL_ACCEPTED = 3;

describe("VerifiablePolicyRegistry", function () {
  let registry, governor, other, newGovernor;

  beforeEach(async function () {
    [governor, other, newGovernor] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("VerifiablePolicyRegistry");
    registry = await Registry.deploy();
    await registry.createScope(SCOPE, governor.address, MAX_VALIDITY);
  });

  it("creates a scope only once and rejects a zero governor", async function () {
    await expect(registry.createScope(SCOPE, governor.address, MAX_VALIDITY)).to.be.revertedWithCustomError(
      registry,
      "ScopeAlreadyExists"
    );
    await expect(
      registry.createScope(ethers.id("other"), ethers.ZeroAddress, MAX_VALIDITY)
    ).to.be.revertedWithCustomError(registry, "ZeroAddress");
  });

  it("lets only the governor publish, and stores the version", async function () {
    const hash = ethers.id("policy-v1");
    await expect(
      registry.connect(other).publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash)
    ).to.be.revertedWithCustomError(registry, "NotGovernor");

    await expect(registry.publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash))
      .to.emit(registry, "PolicyPublished");

    expect(await registry.versionCount(SCOPE)).to.equal(1n);
    const [version, policy, inForce] = await registry.currentPolicy(SCOPE);
    expect(version).to.equal(1n);
    expect(policy.contentHash).to.equal(hash);
    expect(policy.uri).to.equal("ipfs://v1");
    expect(inForce).to.equal(true);
  });

  it("enforces mandatory expiry within the scope's maximum validity", async function () {
    const hash = ethers.id("policy-v1");
    await expect(
      registry.publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, 0, ethers.ZeroHash)
    ).to.be.revertedWithCustomError(registry, "InvalidValidity");
    await expect(
      registry.publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, MAX_VALIDITY + 1, ethers.ZeroHash)
    ).to.be.revertedWithCustomError(registry, "InvalidValidity");
  });

  it("reports a policy as no longer in force after it expires", async function () {
    await registry.publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash);
    await time.increase(DAY + 1);
    const [, , inForce] = await registry.currentPolicy(SCOPE);
    expect(inForce).to.equal(false);
  });

  it("accepts an appeal by publishing a version that resolves it", async function () {
    await registry.publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash);
    const uri = "ipfs://appeal-example-edu";
    const appealId = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "string"], [SCOPE, uri]));

    await expect(registry.connect(other).fileAppeal(SCOPE, uri)).to.emit(registry, "AppealFiled").withArgs(appealId, SCOPE, uri);
    await expect(registry.connect(other).fileAppeal(SCOPE, uri)).to.be.revertedWithCustomError(registry, "AppealAlreadyExists");

    await expect(
      registry.publishPolicy(SCOPE, ethers.id("v2"), ethers.ZeroHash, "ipfs://v2", REASON_APPEAL_ACCEPTED, DAY, appealId)
    )
      .to.emit(registry, "AppealResolved")
      .withArgs(appealId, true);

    const appeal = await registry.appeals(appealId);
    expect(appeal.status).to.equal(2n); // Accepted
    const v2 = await registry.getVersion(SCOPE, 2);
    expect(v2.resolvesAppeal).to.equal(appealId);
  });

  it("lets only the governor reject an open appeal", async function () {
    const uri = "ipfs://appeal-2";
    await registry.connect(other).fileAppeal(SCOPE, uri);
    const appealId = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "string"], [SCOPE, uri]));
    await expect(registry.connect(other).rejectAppeal(appealId)).to.be.revertedWithCustomError(registry, "NotGovernor");
    await expect(registry.rejectAppeal(appealId)).to.emit(registry, "AppealResolved").withArgs(appealId, false);
    await expect(registry.rejectAppeal(appealId)).to.be.revertedWithCustomError(registry, "AppealNotOpen");
  });

  it("rotates the governor", async function () {
    await expect(registry.setGovernor(SCOPE, newGovernor.address))
      .to.emit(registry, "GovernorChanged")
      .withArgs(SCOPE, governor.address, newGovernor.address);
    await expect(
      registry.publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash)
    ).to.be.revertedWithCustomError(registry, "NotGovernor");
    await registry
      .connect(newGovernor)
      .publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash);
    expect(await registry.versionCount(SCOPE)).to.equal(1n);
  });
});
