const { expect } = require("chai");
const { ethers } = require("hardhat");

const Role = { Operator: 1, Reviewer: 2, Auditor: 3 };
const Kind = { Deployment: 0, IndependentTest: 1, Conformance: 2 };
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

  async function resolver(kind) {
    const F = await ethers.getContractFactory("IssuerRoleResolver");
    return F.deploy(eas.address, await registry.getAddress(), kind);
  }

  it("accepts a test attestation only from the reviewer of that scope", async function () {
    const r = await resolver(Kind.IndependentTest);
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(true);
    // the operator cannot certify its own deployment as tested
    expect(await r.connect(eas).attest.staticCall(attestation(operator.address, testData(SCOPE)))).to.equal(false);
    expect(await r.connect(eas).attest.staticCall(attestation(stranger.address, testData(SCOPE)))).to.equal(false);
    // the reviewer of another scope is not the reviewer of this one
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(ethers.id("other scope"))))).to.equal(false);
  });

  it("checks the role at issuance time", async function () {
    const r = await resolver(Kind.IndependentTest);
    await registry.setIssuer(SCOPE, reviewer.address, 0);
    expect(await r.connect(eas).attest.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(false);
  });

  it("reads the scope from the right slot for each schema", async function () {
    const dep = await resolver(Kind.Deployment);
    expect(await dep.connect(eas).attest.staticCall(attestation(operator.address, deploymentData(SCOPE)))).to.equal(true);
    const conf = await resolver(Kind.Conformance);
    expect(await conf.connect(eas).attest.staticCall(attestation(auditor.address, conformanceData(SCOPE)))).to.equal(true);
    expect(await conf.scopeOf(conformanceData(SCOPE))).to.equal(SCOPE);
    expect(await dep.scopeOf(deploymentData(SCOPE))).to.equal(SCOPE);
    // the schema kind fixes the role: a reviewer cannot issue a deployment attestation
    expect(await dep.connect(eas).attest.staticCall(attestation(reviewer.address, deploymentData(SCOPE)))).to.equal(false);
    expect(await dep.requiredRole()).to.equal(BigInt(Role.Operator));
    expect(await conf.requiredRole()).to.equal(BigInt(Role.Auditor));
    expect(await dep.version()).to.equal("1.0.0");
  });

  it("refuses a truncated head or a non-canonical string offset", async function () {
    const r = await resolver(Kind.IndependentTest);
    const good = testData(SCOPE);
    // the head is 10 words; cut inside it
    await expect(r.scopeOf(ethers.dataSlice(good, 0, 9 * 32))).to.be.revertedWithCustomError(r, "MalformedAttestation");
    // the first string must start right after the head (0x140)
    const shifted = ethers.concat([ethers.zeroPadValue(ethers.toBeHex(0x160), 32), ethers.dataSlice(good, 32), ethers.ZeroHash]);
    await expect(r.scopeOf(shifted)).to.be.revertedWithCustomError(r, "MalformedAttestation");
    const conf = await resolver(Kind.Conformance);
    await expect(conf.scopeOf(testData(SCOPE))).to.be.revertedWithCustomError(conf, "MalformedAttestation");
    await expect(conf.scopeOf(ethers.dataSlice(conformanceData(SCOPE), 0, 64))).to.be.revertedWithCustomError(conf, "MalformedAttestation");
  });

  it("only accepts calls from EAS, without value, and rejects malformed data", async function () {
    const r = await resolver(Kind.IndependentTest);
    await expect(r.connect(stranger).attest(attestation(reviewer.address, testData(SCOPE)))).to.be.revertedWithCustomError(r, "NotEAS");
    await expect(r.connect(eas).attest(attestation(reviewer.address, testData(SCOPE)), { value: 1 })).to.be.revertedWithCustomError(
      r,
      "NotPayable"
    );
    await expect(r.connect(eas).attest.staticCall(attestation(reviewer.address, "0x1234"))).to.be.revertedWithCustomError(r, "MalformedAttestation");
    expect(await r.isPayable()).to.equal(false);
    expect(await r.connect(eas).revoke.staticCall(attestation(reviewer.address, testData(SCOPE)))).to.equal(true);
    const a = attestation(reviewer.address, testData(SCOPE));
    await expect(r.connect(stranger).revoke(a)).to.be.revertedWithCustomError(r, "NotEAS");
    await expect(r.connect(stranger).multiAttest([a], [0])).to.be.revertedWithCustomError(r, "NotEAS");
    await expect(r.connect(stranger).multiRevoke([a], [0])).to.be.revertedWithCustomError(r, "NotEAS");
    expect(await r.connect(eas).multiRevoke.staticCall([a], [0])).to.equal(true);
  });

  it("refuses value and mismatched batches on every entry point", async function () {
    const r = await resolver(Kind.IndependentTest);
    const a = attestation(reviewer.address, testData(SCOPE));
    await expect(r.connect(eas).multiAttest([a], [0], { value: 1 })).to.be.revertedWithCustomError(r, "NotPayable");
    await expect(r.connect(eas).revoke(a, { value: 1 })).to.be.revertedWithCustomError(r, "NotPayable");
    await expect(r.connect(eas).multiRevoke([a], [0], { value: 1 })).to.be.revertedWithCustomError(r, "NotPayable");
    await expect(r.connect(eas).multiRevoke([a, a], [0])).to.be.revertedWithCustomError(r, "LengthMismatch");
    await expect(r.connect(eas).multiRevoke([a], [1])).to.be.revertedWithCustomError(r, "NotPayable");
  });

  it("checks every attestation in a batch", async function () {
    const r = await resolver(Kind.IndependentTest);
    const good = attestation(reviewer.address, testData(SCOPE));
    const bad = attestation(operator.address, testData(SCOPE));
    expect(await r.connect(eas).multiAttest.staticCall([good, good], [0, 0])).to.equal(true);
    expect(await r.connect(eas).multiAttest.staticCall([good, bad], [0, 0])).to.equal(false);
    await expect(r.connect(eas).multiAttest.staticCall([good, good], [0])).to.be.revertedWithCustomError(r, "LengthMismatch");
    await expect(r.connect(eas).multiAttest.staticCall([good], [1])).to.be.revertedWithCustomError(r, "NotPayable");
  });

  it("refuses an invalid configuration", async function () {
    const F = await ethers.getContractFactory("IssuerRoleResolver");
    await expect(F.deploy(ethers.ZeroAddress, await registry.getAddress(), Kind.Deployment)).to.be.revertedWithCustomError(F, "ZeroAddress");
    await expect(F.deploy(eas.address, ethers.ZeroAddress, Kind.Deployment)).to.be.revertedWithCustomError(F, "ZeroAddress");
    // an out-of-range schema kind is rejected by the ABI decoder
    await expect(F.deploy(eas.address, await registry.getAddress(), 3)).to.be.reverted;
  });
});
