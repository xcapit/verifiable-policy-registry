// SPDX-License-Identifier: AGPL-3.0-only
// Checks that each VPR schema registered in EAS is bound to an IssuerRoleResolver of the matching kind,
// wired to the registry and EAS named in a deployment manifest (VPR-070). Used by scripts/check-eas.js
// and by the integration test against the real EAS contracts.

const path = require("path");
const EAS_SCHEMAS = require(path.join(__dirname, "..", "..", "..", "schemas", "eas-schemas.json"));

// Schema name -> manifest resolver key and IssuerRoleResolver.SchemaKind.
const BINDINGS = {
  "VPR.Deployment.v1": { resolverKey: "deployment", kind: 0n },
  "VPR.IndependentTest.v1": { resolverKey: "independentTest", kind: 1n },
  "VPR.Conformance.v1": { resolverKey: "conformance", kind: 2n },
};

const RESOLVER_ABI = [
  "function kind() view returns (uint8)",
  "function registry() view returns (address)",
  "function eas() view returns (address)",
  "function isPayable() view returns (bool)",
];
const SCHEMA_REGISTRY_ABI = [
  "function getSchema(bytes32 uid) view returns (tuple(bytes32 uid, address resolver, bool revocable, string schema))",
];

/** EAS schema UID: keccak256(abi.encodePacked(schema, resolver, revocable)). */
function schemaUid(ethers, schema, resolver, revocable) {
  return ethers.solidityPackedKeccak256(["string", "address", "bool"], [schema, resolver, revocable]);
}

/**
 * Returns one entry per schema: { name, uid, problems: string[] }. An empty `problems` array means the
 * binding is correct. Never throws for a wrong binding; it reports it.
 */
async function checkEasBindings({ ethers, provider, manifest }) {
  const c = manifest.contracts || {};
  const same = (a, b) => typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();
  const results = [];
  const schemaRegistry = c.easSchemaRegistry ? new ethers.Contract(c.easSchemaRegistry, SCHEMA_REGISTRY_ABI, provider) : null;

  for (const def of EAS_SCHEMAS.schemas) {
    const binding = BINDINGS[def.name];
    const uid = (c.easSchemaUids || {})[def.name];
    const expectedResolver = (c.resolvers || {})[binding.resolverKey];
    const problems = [];
    if (!c.eas || !c.easSchemaRegistry) problems.push("manifest lacks contracts.eas or contracts.easSchemaRegistry");
    if (!uid) problems.push("manifest lacks the schema UID");
    if (!expectedResolver) problems.push(`manifest lacks contracts.resolvers.${binding.resolverKey}`);
    if (problems.length) {
      results.push({ name: def.name, uid, problems });
      continue;
    }

    const record = await schemaRegistry.getSchema(uid);
    if (record.uid !== uid) problems.push("schema UID not registered in the SchemaRegistry");
    if (record.schema !== def.schema) problems.push("registered schema string differs from schemas/eas-schemas.json");
    if (record.revocable !== def.revocable) problems.push("registered revocability differs from schemas/eas-schemas.json");
    if (!same(record.resolver, expectedResolver)) problems.push("registered resolver differs from the manifest");
    if (uid !== schemaUid(ethers, def.schema, expectedResolver, def.revocable)) {
      problems.push("UID does not match keccak256(schema, resolver, revocable)");
    }

    if ((await provider.getCode(expectedResolver)) === "0x") {
      problems.push("no contract at the manifest resolver address");
    } else {
      const resolver = new ethers.Contract(expectedResolver, RESOLVER_ABI, provider);
      try {
        if ((await resolver.kind()) !== binding.kind) problems.push("resolver SchemaKind does not match the schema");
        if (!same(await resolver.registry(), c.registry)) problems.push("resolver points to another policy registry");
        if (!same(await resolver.eas(), c.eas)) problems.push("resolver accepts calls from another EAS");
        if (await resolver.isPayable()) problems.push("resolver is payable");
      } catch (e) {
        problems.push("resolver does not expose the IssuerRoleResolver interface");
      }
    }
    results.push({ name: def.name, uid, problems });
  }
  return results;
}

module.exports = { BINDINGS, EAS_SCHEMAS, schemaUid, checkEasBindings };
