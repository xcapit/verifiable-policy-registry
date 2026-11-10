// Integration of IssuerRoleResolver with the real Ethereum Attestation Service contracts (VPR-070).
// EAS and SchemaRegistry are deployed from the compiled artifacts published in
// @ethereum-attestation-service/eas-contracts (pinned version), so the resolver is exercised through
// EAS itself rather than through a hand-copied Attestation struct.
const { expect } = require("chai");
const { ethers } = require("hardhat");
const EAS_ARTIFACT = require("@ethereum-attestation-service/eas-contracts/artifacts/contracts/EAS.sol/EAS.json");
const REGISTRY_ARTIFACT = require("@ethereum-attestation-service/eas-contracts/artifacts/contracts/SchemaRegistry.sol/SchemaRegistry.json");
const { EAS_SCHEMAS, schemaUid, checkEasBindings, easVersions } = require("../scripts/lib/eas-check");

const Role = { None: 0, Operator: 1, Reviewer: 2, Auditor: 3 };
const Kind = { Deployment: 0, IndependentTest: 1, Conformance: 2 };
const coder = ethers.AbiCoder.defaultAbiCoder();
const schemaDef = (name) => EAS_SCHEMAS.schemas.find((s) => s.name === name);

function encode(name, scopeId) {
  if (name === "VPR.Deployment.v1") {
    return coder.encode(["string", "bytes32", "uint256", "bytes32", "uint64"], ["giga-0001", scopeId, 1, ethers.id("zone"), 1]);
  }
  if (name === "VPR.IndependentTest.v1") {
    return coder.encode(
      ["string", "bytes32", "uint256", "bool", "bool", "bool", "bool", "bytes32", "uint64", "uint64"],
      ["giga-0001", scopeId, 1, true, true, true, true, ethers.id("report"), 1, 2]
    );
  }
  return coder.encode(["bytes32", "string", "string", "bytes32", "uint64", "uint64"], [scopeId, "NIST SP 800-81r3", "r3", ethers.id("r"), 1, 2]);
}

describe("IssuerRoleResolver with the real EAS contracts", function () {
  let governor, operator, reviewer, auditor, stranger;
  let schemaRegistry, eas, registry, SCOPE, resolvers, uids, manifest;

  // The UID depends on the block timestamp, so it is read from the Attested event, never from a staticCall.
  async function attest(signer, req) {
    const receipt = await (await eas.connect(signer).attest(req)).wait();
    const log = receipt.logs.map((l) => eas.interface.parseLog(l)).find((e) => e && e.name === "Attested");
    expect(log, "Attested event").to.not.equal(undefined);
    return log.args.uid;
  }

  function request(uid, data) {
    return { schema: uid, data: { recipient: ethers.ZeroAddress, expirationTime: 0, revocable: true, refUID: ethers.ZeroHash, data, value: 0 } };
  }

  beforeEach(async function () {
    [governor, operator, reviewer, auditor, stranger] = await ethers.getSigners();
    schemaRegistry = await new ethers.ContractFactory(REGISTRY_ARTIFACT.abi, REGISTRY_ARTIFACT.bytecode, governor).deploy();
    eas = await new ethers.ContractFactory(EAS_ARTIFACT.abi, EAS_ARTIFACT.bytecode, governor).deploy(await schemaRegistry.getAddress());

    registry = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
    await registry.createScope("giga:XX:primary", 90 * 86400);
    SCOPE = await registry.scopeIdOf(governor.address, "giga:XX:primary");
    await registry.setIssuer(SCOPE, operator.address, Role.Operator);
    await registry.setIssuer(SCOPE, reviewer.address, Role.Reviewer);
    await registry.setIssuer(SCOPE, auditor.address, Role.Auditor);

    const F = await ethers.getContractFactory("IssuerRoleResolver");
    resolvers = {};
    uids = {};
    for (const [name, kind] of [
      ["VPR.Deployment.v1", Kind.Deployment],
      ["VPR.IndependentTest.v1", Kind.IndependentTest],
      ["VPR.Conformance.v1", Kind.Conformance],
    ]) {
      const r = await F.deploy(await eas.getAddress(), await registry.getAddress(), kind);
      const def = schemaDef(name);
      await schemaRegistry.register(def.schema, await r.getAddress(), def.revocable);
      resolvers[name] = r;
      uids[name] = schemaUid(ethers, def.schema, await r.getAddress(), def.revocable);
    }
    manifest = {
      chainId: 31337,
      contracts: {
        registry: await registry.getAddress(),
        eas: await eas.getAddress(),
        easSchemaRegistry: await schemaRegistry.getAddress(),
        resolvers: {
          deployment: await resolvers["VPR.Deployment.v1"].getAddress(),
          independentTest: await resolvers["VPR.IndependentTest.v1"].getAddress(),
          conformance: await resolvers["VPR.Conformance.v1"].getAddress(),
        },
        easSchemaUids: { ...uids },
      },
    };
  });

  it("issues each schema only from the holder of its role, through EAS", async function () {
    const cases = [
      ["VPR.Deployment.v1", operator, [reviewer, auditor, governor]],
      ["VPR.IndependentTest.v1", reviewer, [operator, auditor, governor]],
      ["VPR.Conformance.v1", auditor, [operator, reviewer, stranger]],
    ];
    for (const [name, holder, others] of cases) {
      const req = request(uids[name], encode(name, SCOPE));
      const uid = await attest(holder, req);
      const att = await eas.getAttestation(uid);
      expect(att.attester).to.equal(holder.address);
      expect(att.schema).to.equal(uids[name]);
      for (const other of others) {
        await expect(eas.connect(other).attest(req)).to.be.revertedWithCustomError(eas, "InvalidAttestation");
      }
    }
  });

  it("the operator cannot certify its own deployment as tested", async function () {
    const name = "VPR.IndependentTest.v1";
    await expect(eas.connect(operator).attest(request(uids[name], encode(name, SCOPE)))).to.be.revertedWithCustomError(eas, "InvalidAttestation");
  });

  it("refuses a role holder of another scope and a withdrawn role", async function () {
    const name = "VPR.IndependentTest.v1";
    await expect(eas.connect(reviewer).attest(request(uids[name], encode(name, ethers.id("other scope"))))).to.be.revertedWithCustomError(
      eas,
      "InvalidAttestation"
    );
    const req = request(uids[name], encode(name, SCOPE));
    const earlier = await attest(reviewer, req);
    await registry.setIssuer(SCOPE, reviewer.address, Role.None);
    await expect(eas.connect(reviewer).attest(req)).to.be.revertedWithCustomError(eas, "InvalidAttestation");
    // documented limitation: an attestation issued while the role was held stays valid on EAS
    const kept = await eas.getAttestation(earlier);
    expect(kept.attester).to.equal(reviewer.address);
    expect(kept.revocationTime).to.equal(0n);
  });

  it("lets the attester revoke, and EAS keeps the revocation time", async function () {
    const name = "VPR.IndependentTest.v1";
    const req = request(uids[name], encode(name, SCOPE));
    const uid = await attest(reviewer, req);
    await expect(eas.connect(operator).revoke({ schema: uids[name], data: { uid, value: 0 } })).to.be.revertedWithCustomError(eas, "AccessDenied");
    await eas.connect(reviewer).revoke({ schema: uids[name], data: { uid, value: 0 } });
    expect((await eas.getAttestation(uid)).revocationTime).to.be.greaterThan(0n);
  });

  it("rejects a whole batch if one attestation is not authorised", async function () {
    const name = "VPR.IndependentTest.v1";
    const good = request(uids[name], encode(name, SCOPE)).data;
    const bad = request(uids[name], encode(name, ethers.id("other scope"))).data;
    await expect(eas.connect(reviewer).multiAttest([{ schema: uids[name], data: [good, good] }])).to.not.be.reverted;
    await expect(eas.connect(reviewer).multiAttest([{ schema: uids[name], data: [good, bad] }])).to.be.revertedWithCustomError(
      eas,
      "InvalidAttestations"
    );
  });

  it("rejects malformed data and attestations that carry value", async function () {
    const name = "VPR.IndependentTest.v1";
    const r = resolvers[name];
    await expect(eas.connect(reviewer).attest(request(uids[name], "0x1234"))).to.be.revertedWithCustomError(r, "MalformedAttestation");
    // Conformance-encoded data under the IndependentTest schema fails the head check
    await expect(eas.connect(reviewer).attest(request(uids[name], encode("VPR.Conformance.v1", SCOPE)))).to.be.revertedWithCustomError(
      r,
      "MalformedAttestation"
    );
    const paid = request(uids[name], encode(name, SCOPE));
    paid.data.value = 1;
    await expect(eas.connect(reviewer).attest(paid, { value: 1 })).to.be.revertedWithCustomError(eas, "NotPayable");
  });

  describe("deployment check of schema bindings", function () {
    it("accepts a correct deployment and reports the EAS versions", async function () {
      const versions = await easVersions({ ethers, provider: ethers.provider, manifest });
      expect(versions.eas).to.equal("1.4.0");
      expect(versions.schemaRegistry).to.equal("1.4.0");
      const results = await checkEasBindings({ ethers, provider: ethers.provider, manifest });
      expect(results).to.have.length(3);
      for (const r of results) expect(r.problems, r.name).to.deep.equal([]);
    });

    it("detects a schema registered with a resolver of the wrong kind", async function () {
      const def = schemaDef("VPR.IndependentTest.v1");
      const wrong = await resolvers["VPR.Deployment.v1"].getAddress();
      await schemaRegistry.register(def.schema, wrong, def.revocable);
      manifest.contracts.resolvers.independentTest = wrong;
      manifest.contracts.easSchemaUids["VPR.IndependentTest.v1"] = schemaUid(ethers, def.schema, wrong, def.revocable);
      const results = await checkEasBindings({ ethers, provider: ethers.provider, manifest });
      const r = results.find((x) => x.name === "VPR.IndependentTest.v1");
      expect(r.problems).to.include("resolver SchemaKind does not match the schema");
    });

    it("detects a resolver wired to another registry, and a manifest that disagrees with the chain", async function () {
      const other = await (await ethers.getContractFactory("VerifiablePolicyRegistry")).deploy();
      const def = schemaDef("VPR.Conformance.v1");
      const stray = await (await ethers.getContractFactory("IssuerRoleResolver")).deploy(await eas.getAddress(), await other.getAddress(), Kind.Conformance);
      await schemaRegistry.register(def.schema, await stray.getAddress(), def.revocable);
      manifest.contracts.resolvers.conformance = await stray.getAddress();
      manifest.contracts.easSchemaUids["VPR.Conformance.v1"] = schemaUid(ethers, def.schema, await stray.getAddress(), def.revocable);
      // the manifest also names a resolver that is not the one registered for the deployment schema
      manifest.contracts.resolvers.deployment = stranger.address;
      const results = await checkEasBindings({ ethers, provider: ethers.provider, manifest });
      expect(results.find((x) => x.name === "VPR.Conformance.v1").problems).to.include("resolver points to another policy registry");
      const dep = results.find((x) => x.name === "VPR.Deployment.v1").problems;
      expect(dep).to.include("registered resolver differs from the manifest");
      expect(dep).to.include("no contract at the manifest resolver address");
    });
  });
});
