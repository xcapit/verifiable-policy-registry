const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const SCOPE = ethers.id("giga:XX:primary");
const DAY = 24 * 60 * 60;
const MAX_VALIDITY = 90 * DAY;
const REASON_INITIAL = 1;
const REASON_APPEAL_ACCEPTED = 3;
const Role = { None: 0, Operator: 1, Reviewer: 2, Auditor: 3 };
const Status = { None: 0n, Open: 1n, Accepted: 2n, Rejected: 3n };

function appealId(scope, documentHash, round) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32", "uint32"], [scope, documentHash, round]));
}

describe("VerifiablePolicyRegistry", function () {
  let registry, governor, other, newGovernor, operator, reviewer;

  beforeEach(async function () {
    [governor, other, newGovernor, operator, reviewer] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("VerifiablePolicyRegistry");
    registry = await Registry.deploy();
    await registry.connect(governor).createScope(SCOPE, governor.address, MAX_VALIDITY);
  });

  describe("scopes", function () {
    it("creates a scope only once and rejects a zero governor", async function () {
      await expect(registry.createScope(SCOPE, governor.address, MAX_VALIDITY)).to.be.revertedWithCustomError(
        registry,
        "ScopeAlreadyExists"
      );
      await expect(registry.createScope(ethers.id("other"), ethers.ZeroAddress, MAX_VALIDITY)).to.be.revertedWithCustomError(
        registry,
        "ZeroAddress"
      );
    });

    it("only lets the governor create its own scope", async function () {
      await expect(
        registry.connect(other).createScope(ethers.id("giga:YY:primary"), governor.address, MAX_VALIDITY)
      ).to.be.revertedWithCustomError(registry, "NotGovernor");
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

  describe("issuer roles", function () {
    it("lets only the governor assign roles, one role per address", async function () {
      await expect(registry.connect(other).setIssuer(SCOPE, operator.address, Role.Operator)).to.be.revertedWithCustomError(
        registry,
        "NotGovernor"
      );
      await expect(registry.setIssuer(SCOPE, operator.address, Role.Operator))
        .to.emit(registry, "IssuerSet")
        .withArgs(SCOPE, operator.address, Role.Operator);
      await registry.setIssuer(SCOPE, reviewer.address, Role.Reviewer);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.Operator);
      expect(await registry.issuerRole(SCOPE, reviewer.address)).to.equal(Role.Reviewer);

      // assigning another role replaces the previous one: the operator cannot also be the reviewer
      await registry.setIssuer(SCOPE, operator.address, Role.Reviewer);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.Reviewer);
      await registry.setIssuer(SCOPE, operator.address, Role.None);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.None);
      await expect(registry.setIssuer(SCOPE, ethers.ZeroAddress, Role.Auditor)).to.be.revertedWithCustomError(
        registry,
        "ZeroAddress"
      );
    });
  });

  describe("policies", function () {
    it("lets only the governor publish, and stores the version", async function () {
      const hash = ethers.id("policy-v1");
      await expect(
        registry.connect(other).publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash)
      ).to.be.revertedWithCustomError(registry, "NotGovernor");

      await expect(registry.publishPolicy(SCOPE, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash)).to.emit(
        registry,
        "PolicyPublished"
      );

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
  });

  describe("appeals", function () {
    const doc = ethers.id("vpr-appeal/2: unblock educational-site.example");

    it("stores only the document hash and accepts through a new version", async function () {
      await registry.publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, DAY, ethers.ZeroHash);
      const id = appealId(SCOPE, doc, 1);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.emit(registry, "AppealFiled").withArgs(id, SCOPE, doc, 1);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.be.revertedWithCustomError(registry, "AppealAlreadyExists");

      const v2 = ethers.id("v2");
      await expect(registry.publishPolicy(SCOPE, v2, ethers.ZeroHash, "ipfs://v2", REASON_APPEAL_ACCEPTED, DAY, id))
        .to.emit(registry, "AppealResolved")
        .withArgs(id, true, v2);

      const appeal = await registry.appeals(id);
      expect(appeal.status).to.equal(Status.Accepted);
      expect(appeal.documentHash).to.equal(doc);
      expect(appeal.resolutionHash).to.equal(v2);
      expect((await registry.getVersion(SCOPE, 2)).resolvesAppeal).to.equal(id);
      // an accepted appeal cannot be filed again
      await expect(registry.fileAppeal(SCOPE, doc)).to.be.revertedWithCustomError(registry, "AppealAlreadyExists");
    });

    it("requires a reason to reject, and allows resubmission in a new round", async function () {
      const id1 = appealId(SCOPE, doc, 1);
      await registry.connect(other).fileAppeal(SCOPE, doc);
      await expect(registry.connect(other).rejectAppeal(id1, ethers.id("reason"))).to.be.revertedWithCustomError(
        registry,
        "NotGovernor"
      );
      await expect(registry.rejectAppeal(id1, ethers.ZeroHash)).to.be.revertedWithCustomError(registry, "EmptyReason");
      const reason = ethers.id("reasoned decision, published off-chain");
      await expect(registry.rejectAppeal(id1, reason)).to.emit(registry, "AppealResolved").withArgs(id1, false, reason);
      await expect(registry.rejectAppeal(id1, reason)).to.be.revertedWithCustomError(registry, "AppealNotOpen");

      const id2 = appealId(SCOPE, doc, 2);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.emit(registry, "AppealFiled").withArgs(id2, SCOPE, doc, 2);
      expect(await registry.appealIdOf(SCOPE, doc, 2)).to.equal(id2);
      expect((await registry.appeals(id2)).status).to.equal(Status.Open);
    });

    it("rejects empty documents, unknown scopes and appeals from another scope", async function () {
      await expect(registry.fileAppeal(SCOPE, ethers.ZeroHash)).to.be.revertedWithCustomError(registry, "EmptyDocumentHash");
      await expect(registry.fileAppeal(ethers.id("nope"), doc)).to.be.revertedWithCustomError(registry, "UnknownScope");

      const scope2 = ethers.id("giga:XX:secondary");
      await registry.connect(governor).createScope(scope2, governor.address, MAX_VALIDITY);
      await registry.fileAppeal(scope2, doc);
      await expect(
        registry.publishPolicy(SCOPE, ethers.id("v1"), ethers.ZeroHash, "ipfs://v1", REASON_APPEAL_ACCEPTED, DAY, appealId(scope2, doc, 1))
      ).to.be.revertedWithCustomError(registry, "AppealScopeMismatch");
    });
  });
});
