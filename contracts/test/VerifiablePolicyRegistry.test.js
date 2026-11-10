const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const NAME = "giga:XX:primary";
const DAY = 24 * 60 * 60;
const MAX_VALIDITY = 90 * DAY;
const REASON_INITIAL = 1;
const REASON_APPEAL_ACCEPTED = 3;
const Role = { None: 0, Operator: 1, Reviewer: 2, Auditor: 3 };
const Status = { None: 0n, Open: 1n, Accepted: 2n, Rejected: 3n };
// Shared vector with tools/tests/test_review_regressions.py: scopeIdOf(Hardhat account #0, "giga:XX:primary").
const ACCOUNT0 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const SCOPE_ID_VECTOR = "0x8ed60dd6aab12c6e2f1a8fce4a8e3417f75ce71c0f10705b20241392abef33fb";

function appealId(scope, documentHash, round) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32", "uint32"], [scope, documentHash, round]));
}

describe("VerifiablePolicyRegistry", function () {
  let registry, governor, other, newGovernor, operator, reviewer, SCOPE;

  async function publish(signer, scope, hash, opts = {}) {
    return registry
      .connect(signer)
      .publishPolicy(scope, hash, ethers.ZeroHash, opts.uri ?? "ipfs://v", opts.reason ?? REASON_INITIAL, opts.validity ?? DAY, opts.appeal ?? ethers.ZeroHash);
  }

  beforeEach(async function () {
    [governor, other, newGovernor, operator, reviewer] = await ethers.getSigners();
    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await registry.connect(governor).createScope(NAME, MAX_VALIDITY);
    SCOPE = await registry.scopeIdOf(governor.address, NAME);
  });

  describe("scopes", function () {
    it("announces a new scope with its id, creator, name and maximum validity", async function () {
      const name = "giga:XX:secondary";
      const id = await registry.scopeIdOf(other.address, name);
      await expect(registry.connect(other).createScope(name, 30 * DAY))
        .to.emit(registry, "ScopeCreated")
        .withArgs(id, other.address, name, 30 * DAY);
    });

    it("derives the scope id from the governor and the name (shared vector)", async function () {
      expect(governor.address).to.equal(ACCOUNT0);
      expect(SCOPE).to.equal(SCOPE_ID_VECTOR);
      expect(SCOPE).to.equal(ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "string"], [ACCOUNT0, NAME])));
      expect((await registry.scopes(SCOPE)).governor).to.equal(governor.address);
      expect(await registry.scopeName(SCOPE)).to.equal(NAME);
    });

    it("cannot be front-run: the same name by another address is a different scope", async function () {
      await registry.connect(other).createScope(NAME, MAX_VALIDITY);
      const otherScope = await registry.scopeIdOf(other.address, NAME);
      expect(otherScope).to.not.equal(SCOPE);
      expect((await registry.scopes(SCOPE)).governor).to.equal(governor.address);
      await expect(registry.connect(governor).createScope(NAME, MAX_VALIDITY)).to.be.revertedWithCustomError(registry, "ScopeAlreadyExists");
    });

    it("bounds maxValidity and rejects empty names", async function () {
      await expect(registry.createScope("x", 0)).to.be.revertedWithCustomError(registry, "InvalidValidity");
      await expect(registry.createScope("x", 366 * DAY)).to.be.revertedWithCustomError(registry, "InvalidValidity");
      await expect(registry.createScope("", DAY)).to.be.revertedWithCustomError(registry, "EmptyName");
      await expect(registry.createScope("n".repeat(129), DAY)).to.be.revertedWithCustomError(registry, "NameTooLong");
      await registry.createScope("n".repeat(128), DAY);
      await registry.createScope("x", 365 * DAY);
    });

    it("hands over the governor in two steps", async function () {
      await expect(registry.connect(other).proposeGovernor(SCOPE, other.address)).to.be.revertedWithCustomError(registry, "NotGovernor");
      await expect(registry.proposeGovernor(SCOPE, newGovernor.address))
        .to.emit(registry, "GovernorProposed")
        .withArgs(SCOPE, governor.address, newGovernor.address);
      // nothing changes until the new governor accepts
      expect((await registry.scopes(SCOPE)).governor).to.equal(governor.address);
      await expect(registry.connect(other).acceptGovernor(SCOPE)).to.be.revertedWithCustomError(registry, "NotPendingGovernor");
      await expect(registry.connect(newGovernor).acceptGovernor(SCOPE))
        .to.emit(registry, "GovernorChanged")
        .withArgs(SCOPE, governor.address, newGovernor.address);
      await expect(publish(governor, SCOPE, ethers.id("v1"))).to.be.revertedWithCustomError(registry, "NotGovernor");
      await publish(newGovernor, SCOPE, ethers.id("v1"));
      expect(await registry.versionCount(SCOPE)).to.equal(1n);
    });

    it("cancels a pending handover by proposing the zero address", async function () {
      await registry.proposeGovernor(SCOPE, newGovernor.address);
      await registry.proposeGovernor(SCOPE, ethers.ZeroAddress);
      await expect(registry.connect(newGovernor).acceptGovernor(SCOPE)).to.be.revertedWithCustomError(registry, "NotPendingGovernor");
    });

    it("never lets an issuer become governor, nor the pending governor become an issuer", async function () {
      await registry.setIssuer(SCOPE, reviewer.address, Role.Reviewer);
      await expect(registry.proposeGovernor(SCOPE, reviewer.address)).to.be.revertedWithCustomError(registry, "GovernorCannotHoldRole");
      await registry.proposeGovernor(SCOPE, newGovernor.address);
      await expect(registry.setIssuer(SCOPE, newGovernor.address, Role.Reviewer)).to.be.revertedWithCustomError(
        registry,
        "GovernorCannotHoldRole"
      );
      // once its role is revoked, a former issuer can be proposed and accept
      await registry.proposeGovernor(SCOPE, ethers.ZeroAddress);
      await registry.setIssuer(SCOPE, operator.address, Role.Operator);
      await registry.setIssuer(SCOPE, operator.address, Role.None);
      await registry.proposeGovernor(SCOPE, operator.address);
      await registry.connect(operator).acceptGovernor(SCOPE);
      expect((await registry.scopes(SCOPE)).governor).to.equal(operator.address);
    });

    it("refuses a handover for an unknown scope", async function () {
      await expect(registry.proposeGovernor(ethers.id("nope"), other.address)).to.be.revertedWithCustomError(registry, "UnknownScope");
      await expect(registry.acceptGovernor(ethers.id("nope"))).to.be.revertedWithCustomError(registry, "UnknownScope");
    });
  });

  describe("issuer roles", function () {
    it("lets only the governor assign roles, one role per address, never to itself", async function () {
      await expect(registry.connect(other).setIssuer(SCOPE, operator.address, Role.Operator)).to.be.revertedWithCustomError(registry, "NotGovernor");
      await expect(registry.setIssuer(SCOPE, governor.address, Role.Reviewer)).to.be.revertedWithCustomError(
        registry,
        "GovernorCannotHoldRole"
      );
      await expect(registry.setIssuer(SCOPE, operator.address, Role.Operator)).to.emit(registry, "IssuerSet").withArgs(SCOPE, operator.address, Role.Operator);
      await registry.setIssuer(SCOPE, reviewer.address, Role.Reviewer);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.Operator);
      await registry.setIssuer(SCOPE, operator.address, Role.Reviewer);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.Reviewer);
      await registry.setIssuer(SCOPE, operator.address, Role.None);
      expect(await registry.issuerRole(SCOPE, operator.address)).to.equal(Role.None);
      await expect(registry.setIssuer(SCOPE, ethers.ZeroAddress, Role.Auditor)).to.be.revertedWithCustomError(registry, "ZeroAddress");
    });
  });

  describe("policies", function () {
    it("lets only the governor publish, and stores the version", async function () {
      const hash = ethers.id("policy-v1");
      await expect(publish(other, SCOPE, hash)).to.be.revertedWithCustomError(registry, "NotGovernor");
      // every argument of the event is checked: indexers rebuild the policy history from it
      const t = (await time.latest()) + 100;
      await time.setNextBlockTimestamp(t);
      await expect(publish(governor, SCOPE, hash, { uri: "ipfs://v1" }))
        .to.emit(registry, "PolicyPublished")
        .withArgs(SCOPE, 1, hash, ethers.ZeroHash, "ipfs://v1", REASON_INITIAL, t + DAY, ethers.ZeroHash);
      const [version, policy, inForce] = await registry.currentPolicy(SCOPE);
      expect(version).to.equal(1n);
      expect(policy.contentHash).to.equal(hash);
      expect(policy.uri).to.equal("ipfs://v1");
      expect(inForce).to.equal(true);
    });

    it("enforces mandatory expiry within the scope's maximum validity", async function () {
      await expect(publish(governor, SCOPE, ethers.id("v"), { validity: 0 })).to.be.revertedWithCustomError(registry, "InvalidValidity");
      await expect(publish(governor, SCOPE, ethers.id("v"), { validity: MAX_VALIDITY + 1 })).to.be.revertedWithCustomError(
        registry,
        "InvalidValidity"
      );
    });

    it("validates reason codes and their link to appeals", async function () {
      await expect(publish(governor, SCOPE, ethers.id("v"), { reason: 0 })).to.be.revertedWithCustomError(registry, "InvalidReasonCode");
      await expect(publish(governor, SCOPE, ethers.id("v"), { reason: 7 })).to.be.revertedWithCustomError(registry, "InvalidReasonCode");
      // code 3 requires an appeal, and an appeal requires code 3
      await expect(publish(governor, SCOPE, ethers.id("v"), { reason: REASON_APPEAL_ACCEPTED })).to.be.revertedWithCustomError(
        registry,
        "InvalidReasonCode"
      );
    });

    it("caps the length of the policy URI", async function () {
      await expect(publish(governor, SCOPE, ethers.id("v"), { uri: "x".repeat(257) })).to.be.revertedWithCustomError(registry, "UriTooLong");
      await publish(governor, SCOPE, ethers.id("v"), { uri: "x".repeat(256) });
    });

    it("refuses an empty content hash and reports no policy before the first version", async function () {
      const [version, , inForce] = await registry.currentPolicy(SCOPE);
      expect(version).to.equal(0n);
      expect(inForce).to.equal(false);
      await expect(publish(governor, SCOPE, ethers.ZeroHash)).to.be.revertedWithCustomError(registry, "EmptyContentHash");
    });

    it("reverts cleanly for a version that does not exist", async function () {
      await expect(registry.getVersion(SCOPE, 0)).to.be.revertedWithCustomError(registry, "UnknownVersion");
      await expect(registry.getVersion(SCOPE, 1)).to.be.revertedWithCustomError(registry, "UnknownVersion");
      await publish(governor, SCOPE, ethers.id("v1"));
      expect((await registry.getVersion(SCOPE, 1)).contentHash).to.equal(ethers.id("v1"));
    });

    it("accepts the boundary values of validity and reason codes", async function () {
      await publish(governor, SCOPE, ethers.id("v1"), { validity: MAX_VALIDITY, reason: 6 });
    });

    it("reports a policy as no longer in force after it expires", async function () {
      await publish(governor, SCOPE, ethers.id("v1"));
      await time.increase(DAY + 1);
      const [, , inForce] = await registry.currentPolicy(SCOPE);
      expect(inForce).to.equal(false);
    });
  });

  describe("appeals", function () {
    const doc = ethers.id("vpr-appeal/3: unblock educational-site.example, nonce …");

    it("stores only the document hash and accepts through a new version", async function () {
      await publish(governor, SCOPE, ethers.id("v1"));
      const id = appealId(SCOPE, doc, 1);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.emit(registry, "AppealFiled").withArgs(id, SCOPE, doc, 1);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.be.revertedWithCustomError(registry, "AppealAlreadyExists");
      // an appeal requires reason code 3
      await expect(publish(governor, SCOPE, ethers.id("v2"), { appeal: id })).to.be.revertedWithCustomError(registry, "InvalidReasonCode");
      const v2 = ethers.id("v2");
      await expect(publish(governor, SCOPE, v2, { reason: REASON_APPEAL_ACCEPTED, appeal: id }))
        .to.emit(registry, "AppealResolved")
        .withArgs(id, true, v2);
      const appeal = await registry.appeals(id);
      expect(appeal.status).to.equal(Status.Accepted);
      expect(appeal.resolutionHash).to.equal(v2);
      await expect(registry.fileAppeal(SCOPE, doc)).to.be.revertedWithCustomError(registry, "AppealAlreadyExists");
    });

    it("requires a reason to reject, and allows resubmission in a new round", async function () {
      const id1 = appealId(SCOPE, doc, 1);
      await registry.connect(other).fileAppeal(SCOPE, doc);
      await expect(registry.connect(other).rejectAppeal(id1, ethers.id("r"))).to.be.revertedWithCustomError(registry, "NotGovernor");
      await expect(registry.rejectAppeal(id1, ethers.ZeroHash)).to.be.revertedWithCustomError(registry, "EmptyReason");
      const reason = ethers.id("reasoned decision");
      await expect(registry.rejectAppeal(id1, reason)).to.emit(registry, "AppealResolved").withArgs(id1, false, reason);
      const id2 = appealId(SCOPE, doc, 2);
      await expect(registry.connect(other).fileAppeal(SCOPE, doc)).to.emit(registry, "AppealFiled").withArgs(id2, SCOPE, doc, 2);
      expect(await registry.appealIdOf(SCOPE, doc, 2)).to.equal(id2);
    });

    it("never resolves an appeal twice, by acceptance or rejection", async function () {
      const id = appealId(SCOPE, doc, 1);
      await registry.connect(other).fileAppeal(SCOPE, doc);
      await publish(governor, SCOPE, ethers.id("v1"), { reason: REASON_APPEAL_ACCEPTED, appeal: id });
      await expect(publish(governor, SCOPE, ethers.id("v2"), { reason: REASON_APPEAL_ACCEPTED, appeal: id })).to.be.revertedWithCustomError(
        registry,
        "AppealNotOpen"
      );
      await expect(registry.rejectAppeal(id, ethers.id("late"))).to.be.revertedWithCustomError(registry, "AppealNotOpen");
    });

    it("rejects empty documents, unknown scopes and appeals from another scope", async function () {
      await expect(registry.fileAppeal(SCOPE, ethers.ZeroHash)).to.be.revertedWithCustomError(registry, "EmptyDocumentHash");
      await expect(registry.fileAppeal(ethers.id("nope"), doc)).to.be.revertedWithCustomError(registry, "UnknownScope");
      await registry.connect(governor).createScope("giga:XX:secondary", MAX_VALIDITY);
      const scope2 = await registry.scopeIdOf(governor.address, "giga:XX:secondary");
      await registry.fileAppeal(scope2, doc);
      await expect(
        publish(governor, SCOPE, ethers.id("v1"), { reason: REASON_APPEAL_ACCEPTED, appeal: appealId(scope2, doc, 1) })
      ).to.be.revertedWithCustomError(registry, "AppealScopeMismatch");
    });
  });
});
