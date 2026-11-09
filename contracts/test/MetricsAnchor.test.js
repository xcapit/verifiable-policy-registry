const { expect } = require("chai");
const { ethers } = require("hardhat");

const SCOPE = ethers.id("giga:XX:primary");
const MAX_VALIDITY = 90 * 24 * 60 * 60;
const DAY = 20758; // 2026-11-01

// Dataset format 2: domain-separated leaves (0x00) and internal nodes (0x01), as in tools/vpr/merkle.py.
function leafHash(day, school, category, count) {
  const s = ethers.toUtf8Bytes(school);
  const c = ethers.toUtf8Bytes(category);
  return ethers.keccak256(
    ethers.solidityPacked(
      ["bytes1", "uint32", "uint256", "uint16", "bytes", "uint16", "bytes"],
      ["0x00", day, count, s.length, s, c.length, c]
    )
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
  let registry, anchor, governor, publisher, other;
  let leaves, ab, root;

  beforeEach(async function () {
    [governor, publisher, other] = await ethers.getSigners();
    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await registry.connect(governor).createScope(SCOPE, governor.address, MAX_VALIDITY);
    anchor = await (await ethers.getContractFactory("MetricsAnchor")).deploy(await registry.getAddress());
    await anchor.connect(governor).setPublisher(SCOPE, publisher.address);

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

  it("only the governor in the registry appoints the publisher (no first-caller claim)", async function () {
    await expect(anchor.connect(other).setPublisher(SCOPE, other.address)).to.be.revertedWithCustomError(anchor, "NotGovernor");
    await expect(anchor.connect(other).setPublisher(ethers.id("unknown"), other.address)).to.be.revertedWithCustomError(
      anchor,
      "UnknownScope"
    );
    // after a governor rotation, the new governor controls the publisher and the old one does not
    await registry.connect(governor).setGovernor(SCOPE, other.address);
    await expect(anchor.connect(governor).setPublisher(SCOPE, governor.address)).to.be.revertedWithCustomError(
      anchor,
      "NotGovernor"
    );
    await expect(anchor.connect(other).setPublisher(SCOPE, other.address))
      .to.emit(anchor, "PublisherSet")
      .withArgs(SCOPE, other.address, other.address);
  });

  it("only the publisher commits, once per day", async function () {
    await expect(anchor.connect(other).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(
      anchor,
      "NotPublisher"
    );
    await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, ethers.ZeroHash, "ipfs://d")).to.be.revertedWithCustomError(
      anchor,
      "EmptyRoot"
    );
    await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d"))
      .to.emit(anchor, "RootCommitted")
      .withArgs(SCOPE, DAY, root, "ipfs://d");
    await expect(anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d")).to.be.revertedWithCustomError(
      anchor,
      "DayAlreadyCommitted"
    );
  });

  it("verifies published rows and rejects tampered rows, wrong days and internal nodes", async function () {
    await anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d");
    const [s0, c0, n0] = ROWS[0];
    const [s2, c2, n2] = ROWS[2];

    expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(true);
    expect(await anchor.verifyRow(SCOPE, DAY, s2, c2, n2, [ab])).to.equal(true);

    // tampered count
    expect(await anchor.verifyRow(SCOPE, DAY, s0, c0, n0 + 1, [leaves[1], leaves[2]])).to.equal(false);
    // same row claimed for another day: the leaf binds the anchored day
    await anchor.connect(publisher).commitRoot(SCOPE, DAY + 1, root, "ipfs://d2");
    expect(await anchor.verifyRow(SCOPE, DAY + 1, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
    // an unanchored day never verifies
    expect(await anchor.verifyRow(SCOPE, DAY + 2, s0, c0, n0, [leaves[1], leaves[2]])).to.equal(false);
  });

  it("only verifies rows, so an internal node cannot be presented as a leaf", async function () {
    await anchor.connect(publisher).commitRoot(SCOPE, DAY, root, "ipfs://d");
    // with raw-leaf verification, presenting `ab` with proof [leaves[2]] would succeed; rows are hashed with 0x00
    const fakeLeafFromNode = hashPair(ab, leaves[2]);
    expect(fakeLeafFromNode).to.equal(root);
    // there is no row whose 0x00-prefixed leaf equals `ab`, so no call to verifyRow can reproduce that path
    expect(await anchor.verifyRow(SCOPE, DAY, "giga-0001", "adult", 40, [leaves[2]])).to.equal(false);
  });

  it("rejects fields too long for the length-prefixed encoding", async function () {
    const long = "x".repeat(65536);
    await expect(anchor.leafHash(DAY, long, "adult", 1)).to.be.revertedWithCustomError(anchor, "FieldTooLong");
  });
});
