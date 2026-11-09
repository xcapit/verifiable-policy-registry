const { expect } = require("chai");
const { ethers } = require("hardhat");

const SCOPE = ethers.id("giga:XX:primary");

// Sorted-pair keccak256 Merkle tree, same scheme as tools/vpr/merkle.py and OpenZeppelin MerkleProof.
function hashPair(a, b) {
  return a.toLowerCase() < b.toLowerCase()
    ? ethers.keccak256(ethers.concat([a, b]))
    : ethers.keccak256(ethers.concat([b, a]));
}

describe("MetricsAnchor", function () {
  let anchor, admin, publisher, other;

  beforeEach(async function () {
    [admin, publisher, other] = await ethers.getSigners();
    const Anchor = await ethers.getContractFactory("MetricsAnchor");
    anchor = await Anchor.deploy();
    await anchor.configure(SCOPE, admin.address, publisher.address);
  });

  it("only the publisher commits, once per day", async function () {
    const root = ethers.id("root");
    await expect(anchor.connect(other).commitRoot(SCOPE, 20400, root, "ipfs://d")).to.be.revertedWithCustomError(
      anchor,
      "NotPublisher"
    );
    await expect(anchor.connect(publisher).commitRoot(SCOPE, 20400, root, "ipfs://d"))
      .to.emit(anchor, "RootCommitted")
      .withArgs(SCOPE, 20400, root, "ipfs://d");
    await expect(anchor.connect(publisher).commitRoot(SCOPE, 20400, root, "ipfs://d")).to.be.revertedWithCustomError(
      anchor,
      "DayAlreadyCommitted"
    );
  });

  it("verifies a leaf against the committed root", async function () {
    const leaves = ["a", "b", "c"].map((x) => ethers.id(x));
    const ab = hashPair(leaves[0], leaves[1]);
    const root = hashPair(ab, leaves[2]);
    await anchor.connect(publisher).commitRoot(SCOPE, 20401, root, "ipfs://d");

    expect(await anchor.verifyLeaf(SCOPE, 20401, leaves[0], [leaves[1], leaves[2]])).to.equal(true);
    expect(await anchor.verifyLeaf(SCOPE, 20401, leaves[2], [ab])).to.equal(true);
    expect(await anchor.verifyLeaf(SCOPE, 20401, ethers.id("z"), [leaves[1], leaves[2]])).to.equal(false);
  });

  it("lets only the admin rotate the publisher", async function () {
    await expect(anchor.connect(other).setPublisher(SCOPE, other.address)).to.be.revertedWithCustomError(anchor, "NotAdmin");
    await anchor.setPublisher(SCOPE, other.address);
    expect(await anchor.publisher(SCOPE)).to.equal(other.address);
  });
});
