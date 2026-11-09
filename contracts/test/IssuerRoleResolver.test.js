const { expect } = require("chai");
const { ethers } = require("hardhat");

const Role = { Operator: 1, Reviewer: 2, Auditor: 3 };
const coder = ethers.AbiCoder.defaultAbiCoder();

// Encodings of the three EAS schemas in schemas/eas-schemas.json.
function deploymentData(scopeId) {
  return coder.encode(["string", "bytes32", "uint256", "bytes32", "uint64"], ["giga-0001", scopeId, 1, ethers.id("cfg"), 1]);
}
function testData(scopeId) {
  return coder.encode(
    ["string", "bytes32", "uint256", "bool", "bool", "bool", "bool", "bytes32", "uint64", "uint64"],
    ["giga-0001", scopeId, 1, true, true, true, true, ethers.id("report"), 1, 2]
  );
}
function conformanceData(scopeId) {
  return coder.encode(["bytes32", "string", "string", "bytes32", "uint64", "uint64"], [scopeId, "NIST SP 800-81r3", "r3", ethers.id("r"), 1, 2]);
}
function attestation(attester, data) {
  return {
    uid: ethers.id("uid"),
    schema: ethers.id("schema"),
    time: 1,
    expirationTime: 0,
    revocationTime: 0,
    refUID: ethers.ZeroHash,
    recipient: ethers.ZeroAddress,
    attester,
    revocable: true,
    data,
  };
}

describe("IssuerRoleResolver", function () {
  let registry, eas, governor, operator, reviewer, auditor, stranger, SCOPE;

  beforeEach(async function () {
    [governor, eas, operator, reviewer, auditor, stranger] = await ethers.getSigners();
    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await registry.createScope("giga:XX:primary", 90 * 86400);
    SCOPE = await registry.scopeIdOf(governor.address, "giga:XX:primary");
    await registry.setIssuer(SCOPE, operator.address, Role.Operator);
    await registry.setIssuer(SCOPE, reviewer.address, Role.Reviewer);
    await registry.setIssuer(SCOPE, auditor.address, Role.Auditor);
  });

  async function resolver(role, slot) {
    const F = await ethers.getContractFactory("IssuerRoleResolver");
    return F.deploy(eas.address, await registry.getAddress(), role, slot);
  }

  it("accepts a test attestation only from the reviewer of that scope", async function () {
    const r = await resolver(Role.Reviewer, 1);
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(true);
    // the operator cannot certify its own deployment as tested
    expect(await r.connect(eas).attest.staticCall(attestation(operator.address, testData(SCOPE)))).to.equal(false);
    expect(await r.connect(eas).attest.staticCall(attestation(stranger.address, testData(SCOPE)))).to.equal(false);
    // the reviewer of another scope is not the reviewer of this one
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(ethers.id("other scope"))))).to.equal(false);
  });

  it("checks the role at issuance time", async function () {
    const r = await resolver(Role.Reviewer, 1);
    await registry.setIssuer(SCOPE, reviewer.address, 0);
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(false);
  });

  it("reads the scope from the right slot for each schema", async function () {
    const dep = await resolver(Role.Operator, 1);
    expect(await dep.connect(eas).attest.staticCall(attestation(operator.address, deploymentData(SCOPE)))).to.equal(true);
    const conf = await resolver(Role.Auditor, 0);
    expect(await conf.connect(eas).attest.staticCall(attestation(auditor.address, conformanceData(SCOPE)))).to.equal(true);
    expect(await conf.scopeOf(conformanceData(SCOPE))).to.equal(SCOPE);
    expect(await dep.scopeOf(deploymentData(SCOPE))).to.equal(SCOPE);
  });

  it("only accepts calls from EAS, without value, and rejects malformed data", async function () {
    const r = await resolver(Role.Reviewer, 1);
    await expect(r.connect(stranger).attest(attestation(reviewer.address, testData(SCOPE)))).to.be.revertedWithCustomError(r, "NotEAS");
    await expect(r.connect(eas).attest(attestation(reviewer.address, testData(SCOPE)), { value: 1 })).to.be.revertedWithCustomError(
      r,
      "InsufficientValue"
    );
    await expect(r.connect(eas).attest.staticCall(attestation(reviewer.address, "0x1234"))).to.be.revertedWithCustomError(r, "MalformedAttestation");
    expect(await r.isPayable()).to.equal(false);
    expect(await r.connect(eas).revoke.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(true);
  });

  it("checks every attestation in a batch", async function () {
    const r = await resolver(Role.Reviewer, 1);
    const good = attestation(reviewer.address, testData(SCOPE));
    const bad = attestation(operator.address, testData(SCOPE));
    expect(await r.connect(eas).multiAttest.staticCall([good, good], [0, 0])).to.equal(true);
    expect(await r.connect(eas).multiAttest.staticCall([good, bad], [0, 0])).to.equal(false);
  });

  it("refuses an invalid configuration", async function () {
    const F = await ethers.getContractFactory("IssuerRoleResolver");
    await expect(F.deploy(eas.address, await registry.getAddress(), 0, 1)).to.be.revertedWithCustomError(F, "InvalidConfiguration");
    await expect(F.deploy(eas.address, await registry.getAddress(), 2, 2)).to.be.revertedWithCustomError(F, "InvalidConfiguration");
    await expect(F.deploy(ethers.ZeroAddress, await registry.getAddress(), 2, 1)).to.be.revertedWithCustomError(F, "ZeroAddress");
  });
});
