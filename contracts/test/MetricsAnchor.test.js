const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const NAME = "giga:XX:primary";
const MAX_VALIDITY = 90 * 24 * 60 * 60;
const DAY = 20758; // 2026-11-01, in the past for any run of these tests
const NO_LAG_LIMIT = 2 ** 32 - 1;

// Dataset format 2: domain-separated leaves (0x00) and internal nodes (0x01), as in tools/vpr/merkle.py.
function leafHash(day, unit, category, count) {
  const s = ethers.toUtf8Bytes(unit);
  const c = ethers.toUtf8Bytes(category);
  return ethers.keccak256(
    ethers.solidityPacked(["bytes1", "uint32", "uint256", "uint16", "bytes", "uint16", "bytes"], ["0x00", day, count, s.length, s, c.length, c])
  );
}
function hashPair(a, b) {
  const [x, y] = a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a];
  return ethers.keccak256(ethers.concat(["0x01", x, y]));
}

// Shared test vector (also in tools/tests/test_metrics.py).
const ROWS = [
  ["giga-0001", "adult", 40],
  ["giga-0001", "malware", 25],
  ["giga-0003", "malware", 25],
];

describe("MetricsAnchor", function () {
  let registry, anchor, governor, publisher, other, SCOPE;
  let leaves, ab, root;

  async function today() {
    return Number(await anchor.today());
  }

  beforeEach(async function () {
    [governor, publisher, other] = await ethers.getSigners();
    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await registry.connect(governor).createScope(NAME, MAX_VALIDITY);
    SCOPE = await registry.scopeIdOf(governor.address, NAME);
    anchor = await (await ethers.getContractFactory("MetricsAnchor")).deploy(await registry.getAddress());
    await anchor.connect(governor).setPublisher(SCOPE, publisher.address, NO_LAG_LIMIT);

    leaves = ROWS.map(([s, c, n]) => leafHash(DAY, s, c, n));
    ab = hashPair(leaves[0], leaves[1]);
    root = hashPair(ab, leaves[2]);
  });

  it("matches the shared test vector", async function () {
    for (let i = 0; i < ROWS.length; i++) {
      const [s, c, n] = ROWS[i];
      expect(await anchor.leafHash(DAY, s, c, n)).to.equal(leaves[i]);
    }
    expect(leaves[0]).to.equal("0xd16b6d8f55bf68aa54ca8d755e0c0beb5c84c2e63e9eda7ab55abc5579b8a348");
    expect(root).to.equal("0x7d91cbb18fd37a7042393e2043b2fed8a1d0723bdf8845d72bc7188febdf6747");
  });

  describe("publisher", function () {
    it("is appointed only by the governor in the registry (no first-caller claim)", async function () {
      await expect(anchor.connect(other).setPublisher(SCOPE, other.address, 1)).to.be.revertedWithCustomError(anchor, "NotGovernor");
      await expect(anchor.connect(other).setPublisher(ethers.id("unknown"), other.address, 1)).to.be.revertedWithCustomError(
        anchor,
        "UnknownScope"
      );
    });

    it("can be revoked, and follows a completed governor handover", async function () {
      await expect(anchor.setPublisher(SCOPE, ethers.ZeroAddress, 0))
        .to.emit(anchor, "PublisherSet")
        .withArgs(SCOPE, governor.address, ethers.ZeroAddress, 0);
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "NotPublisher");
      await registry.proposeGovernor(SCOPE, other.address);
      await registry.connect(other).acceptGovernor(SCOPE);
      await expect(anchor.connect(governor).setPublisher(SCOPE, governor.address, 1)).to.be.revertedWithCustomError(anchor, "NotGovernor");
      await anchor.connect(other).setPublisher(SCOPE, publisher.address, 7);
      expect(await anchor.maxLagDays(SCOPE)).to.equal(7n);
    });

    it("requires an explicit lag: at least one day for a publisher, zero only to revoke", async function () {
      await expect(anchor.setPublisher(SCOPE, publisher.address, 0)).to.be.revertedWithCustomError(anchor, "InvalidLag");
      await expect(anchor.setPublisher(SCOPE, ethers.ZeroAddress, 1)).to.be.revertedWithCustomError(anchor, "InvalidLag");
    });

    it("keeps the old publisher after a governor handover until the new governor replaces it", async function () {
      await registry.proposeGovernor(SCOPE, other.address);
      await registry.connect(other).acceptGovernor(SCOPE);
      await anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d");
      await anchor.connect(other).setPublisher(SCOPE, ethers.ZeroAddress, 0);
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY + 1, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "NotPublisher");
      // the previous governor can no longer correct the scope's roots
      await expect(anchor.connect(governor).correctRoot(SCOPE, DAY, ethers.id("x"), "ipfs://d2", ethers.id("r"))).to.be.revertedWithCustomError(
        anchor,
        "NotGovernor"
      );
    });
  });

  describe("commitments", function () {
    it("only the publisher commits, once per day, with a bounded URI", async function () {
      await expect(anchor.connect(other).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "NotPublisher");
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, ethers.ZeroHash, "ipfs://d")).to.be.revertedWithCustomError(anchor, "EmptyRoot");
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "x".repeat(257))).to.be.revertedWithCustomError(anchor, "UriTooLong");
      await anchor.connect(publisher).commitRoot(SCOPE, DAY - 1, root, "x".repeat(256));
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.emit(anchor, "RootCommitted").withArgs(SCOPE, DAY, root, "ipfs://d");
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayAlreadyCommitted");
    });

    it("anchors only days that have ended, within the lag limit", async function () {
      const t = await today();
      await expect(anchor.connect(publisher).commitRoot(SCOPE, t + 1, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayNotClosed");
      // the current UTC day is still accumulating
      await expect(anchor.connect(publisher).commitRoot(SCOPE, t, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayNotClosed");
      await expect(anchor.connect(publisher).markEmpty(SCOPE, t)).to.be.revertedWithCustomError(anchor, "DayNotClosed");
      await anchor.setPublisher(SCOPE, publisher.address, 7);
      await expect(anchor.connect(publisher).commitRoot(SCOPE, t - 8, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayTooOld");
      await expect(anchor.connect(publisher).markEmpty(SCOPE, t - 8)).to.be.revertedWithCustomError(anchor, "DayTooOld");
      await anchor.connect(publisher).commitRoot(SCOPE, t - 7, root, "ipfs://d"); // day + lag == today
      // lag 1: yesterday only
      await anchor.setPublisher(SCOPE, publisher.address, 1);
      await expect(anchor.connect(publisher).commitRoot(SCOPE, t - 2, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayTooOld");
      await anchor.connect(publisher).commitRoot(SCOPE, t - 1, root, "ipfs://d");
    });

    it("marks empty days, which then cannot be anchored and never verify", async function () {
      await expect(anchor.connect(publisher).markEmpty(SCOPE, DAY)).to.emit(anchor, "EmptyDayMarked").withArgs(SCOPE, DAY);
      expect((await anchor.getCommitment(SCOPE, DAY)).empty).to.equal(true);
      await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(anchor, "DayAlreadyCommitted");
      const [s0, c0, n0] = ROWS[0];
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
    });

    it("lets only the governor correct a root, with a reason, and counts revisions", async function () {
      const wrong = ethers.id("wrong root");
      await anchor.connect(publisher).commitRoot(SCOPE, DAY, wrong, "ipfs://d");
      const reason = ethers.id("published correction note");
      await expect(anchor.connect(publisher).correctRoot(SCOPE, DAY, root, "ipfs://d2", reason)).to.be.revertedWithCustomError(anchor, "NotGovernor");
      await expect(anchor.correctRoot(SCOPE, DAY + 1, root, "ipfs://d2", reason)).to.be.revertedWithCustomError(anchor, "DayNotCommitted");
      await expect(anchor.correctRoot(SCOPE, DAY, root, "ipfs://d2", ethers.ZeroHash)).to.be.revertedWithCustomError(anchor, "EmptyReason");
      await expect(anchor.correctRoot(SCOPE, DAY, wrong, "ipfs://d2", reason)).to.be.revertedWithCustomError(anchor, "NoChange");
      await expect(anchor.correctRoot(SCOPE, DAY, root, "ipfs://d2", reason))
        .to.emit(anchor, "RootCorrected")
        .withArgs(SCOPE, DAY, wrong, root, "ipfs://d2", reason, 1);
      const c = await anchor.getCommitment(SCOPE, DAY);
      expect(c.root).to.equal(root);
      expect(c.revision).to.equal(1n);
      const [s0, c0, n0] = ROWS[0];
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(true);
    });

    it("refuses a zero registry and an oversized correction URI", async function () {
      const F = await ethers.getContractFactory("MetricsAnchor");
      await expect(F.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(F, "ZeroAddress");
      await anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d");
      await expect(anchor.correctRoot(SCOPE, DAY, ethers.id("x"), "x".repeat(257), ethers.id("r"))).to.be.revertedWithCustomError(
        anchor,
        "UriTooLong"
      );
    });

    it("corrects an empty day into a root and a root back into an empty day", async function () {
      const [s0, c0, n0] = ROWS[0];
      const reason = ethers.id("note");
      await anchor.connect(publisher).markEmpty(SCOPE, DAY);
      await expect(anchor.correctRoot(SCOPE, DAY, ethers.ZeroHash, "", reason)).to.be.revertedWithCustomError(anchor, "NoChange");
      // previousRoot 0 in the event means the day was empty
      await expect(anchor.correctRoot(SCOPE, DAY, root, "ipfs://d", reason))
        .to.emit(anchor, "RootCorrected")
        .withArgs(SCOPE, DAY, ethers.ZeroHash, root, "ipfs://d", reason, 1);
      expect((await anchor.getCommitment(SCOPE, DAY)).empty).to.equal(false);
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(true);
      await anchor.correctRoot(SCOPE, DAY, ethers.ZeroHash, "", reason);
      const c = await anchor.getCommitment(SCOPE, DAY);
      expect(c.empty).to.equal(true);
      expect(c.revision).to.equal(2n);
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
    });
  });

  describe("verification", function () {
    it("verifies published rows and rejects tampered rows, wrong days and unanchored days", async function () {
      await anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d");
      const [s0, c0, n0] = ROWS[0];
      const [s2, c2, n2] = ROWS[2];
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(true);
      expect(await anchor.verifyRow(SCOPE, DAY, s2, c2, n2, [ab])).to.equal(true);
      expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0 + 1, [leaves[1], leaves[2]])).to.equal(false);
      await anchor.connect(publisher).commitRoot(SCOPE, DAY + 1, root, "ipfs://d2");
      expect(await anchor.verifyRow(SCOPE, DAY + 1, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
      expect(await anchor.verifyRow(SCOPE, DAY + 2, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
    });

    it("rejects fields too long for the length-prefixed encoding, and accepts any length up to the limit", async function () {
      await expect(anchor.leafHash(DAY, "x".repeat(65536), "adult", 1)).to.be.revertedWithCustomError(anchor, "FieldTooLong");
      await expect(anchor.leafHash(DAY, "u", "c".repeat(65536), 1)).to.be.revertedWithCustomError(anchor, "FieldTooLong");
      // the limit is the uint16 length prefix: 256 bytes and exactly 65 535 bytes are valid
      await anchor.leafHash(DAY, "x".repeat(256), "c".repeat(256), 1);
      await anchor.leafHash(DAY, "x".repeat(65535), "c".repeat(65535), 1);
    });

    it("exposes the documented sentinel for an unbounded back-fill window", async function () {
      expect(await anchor.NO_LAG_LIMIT()).to.equal(2n ** 32n - 1n);
      expect(await anchor.MAX_URI_LENGTH()).to.equal(256n);
    });
  });
});
