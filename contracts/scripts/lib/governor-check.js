// SPDX-License-Identifier: AGPL-3.0-only
// Checks that the governor of each scope in a deployment manifest is the Safe the manifest declares, with the
// declared threshold. Used by scripts/check-governor.js and by test/GovernorCheck.test.js.
//
// The registry accepts any address as governor, on purpose: whether an address is an m-of-n Safe cannot be
// decided on-chain (an EIP-7702 delegated EOA has code, a contract has no code during its constructor, and
// "has code" is not "is a Safe"). The check is therefore off-chain, read from the chain at the time it runs.
//
// What makes the Safe answers trustworthy: the governor's runtime code must hash to a declared SafeProxy code
// hash, and its storage slot 0 (the proxy's singleton) must be a declared singleton. A SafeProxy delegatecalls
// every call to that singleton, so VERSION(), getThreshold(), getOwners() and getModulesPaginated() are then
// answered by the declared singleton's code over the Safe's own storage, not by code the governor chose.
// The declared values must be the published ones (for example from @safe-global/safe-deployments); this script
// does not know which addresses or hashes are canonical.
//
// Limits: the result holds for the block read; owners, threshold, modules and guard can change afterwards by a
// Safe transaction, so monitors re-run it or watch the Safe's events. It does not check who the owners are.
// Owners and modules are those the Safe enumerates by walking its linked lists from the sentinel. A delegatecall
// made by the Safe (in setup or in a later transaction) can write an owner or module entry that is not linked
// into the list; such an entry still counts for signatures or module execution but is not seen here. The check
// cannot exclude that; a reviewer who needs to should examine the Safe's transaction history.

// Safe stores linked lists with this sentinel as head (ModuleManager, OwnerManager).
const SENTINEL = "0x0000000000000000000000000000000000000001";
const MODULE_PAGE_SIZE = 50;
const MAX_MODULE_PAGES = 20;
// EIP-7702 delegation designator: 0xef0100 || address (23 bytes).
const DELEGATION_PREFIX = "0xef0100";
// Safe 1.3.0 is the first version whose transaction hash covers the chain id (EIP-712 domain with chainId).
const MIN_VERSION = [1, 3, 0];

const REGISTRY_ABI = [
  "function scopes(bytes32) view returns (address governor, uint64 maxValidity, bool exists)",
  "function pendingGovernor(bytes32) view returns (address)",
];
const SAFE_ABI = [
  "function VERSION() view returns (string)",
  "function getThreshold() view returns (uint256)",
  "function getOwners() view returns (address[])",
  "function getModulesPaginated(address start, uint256 pageSize) view returns (address[] array, address next)",
];

const same = (a, b) => typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();

/** Storage slots the Safe uses for its transaction guard and fallback handler (GuardManager, FallbackManager). */
function safeSlots(ethers) {
  return {
    singleton: 0n,
    guard: BigInt(ethers.id("guard_manager.guard.address")),
    fallbackHandler: BigInt(ethers.id("fallback_manager.handler.address")),
  };
}

/** Parses "m-of-n"; returns { m, n } or null if malformed, m < 1 or m > n. */
function parseThreshold(text) {
  const match = /^([0-9]+)-of-([0-9]+)$/.exec(text || "");
  if (!match) return null;
  const m = Number(match[1]);
  const n = Number(match[2]);
  return m >= 1 && m <= n ? { m, n } : null;
}

/** True if a Safe VERSION() string is 1.3.0 or later. */
function versionAtLeast(version, min = MIN_VERSION) {
  const match = /^([0-9]+)\.([0-9]+)\.([0-9]+)/.exec(version || "");
  if (!match) return false;
  for (let i = 0; i < 3; i++) {
    const v = Number(match[i + 1]);
    if (v !== min[i]) return v > min[i];
  }
  return true;
}

async function readAddressSlot(ethers, provider, account, slot, blockTag) {
  const word = await provider.getStorage(account, slot, blockTag);
  return ethers.getAddress(ethers.dataSlice(word, 12));
}

/**
 * Modules the Safe enumerates from its sentinel. The meaning of `next` differs by version: Safe 1.4.x returns the
 * last module of the page, Safe 1.3.0 the first module not in the page (ModuleManager.getModulesPaginated). Both
 * are handled: a `next` that is not the last element of the page is itself a module, and the next page starts
 * after it. Returns { modules, complete }; complete is false if the list is longer than the pages read.
 */
async function enabledModules(safe, at) {
  const modules = [];
  let start = SENTINEL;
  for (let page = 0; page < MAX_MODULE_PAGES; page++) {
    const [array, next] = await safe.getModulesPaginated(start, MODULE_PAGE_SIZE, at);
    modules.push(...array);
    if (same(next, SENTINEL) || next === "0x0000000000000000000000000000000000000000") return { modules, complete: true };
    if (array.length === 0 || !same(next, array[array.length - 1])) modules.push(next);
    start = next;
  }
  return { modules, complete: false };
}

/** Checks the on-chain governor `account` as a Safe; pushes to `problems` and `info`. */
async function checkSafe({ ethers, provider, blockTag, account, declared, threshold, allowedModules, problems, info }) {
  const at = { blockTag };
  const code = await provider.getCode(account, blockTag);
  if (code === "0x") {
    problems.push("governor has no code (an EOA, or a contract not yet deployed), so it is not a Safe");
    return;
  }
  if (code.toLowerCase().startsWith(DELEGATION_PREFIX)) {
    // Stop here: calls to a delegated EOA run the delegate's code, so nothing it answers is evidence.
    problems.push(`governor is an EIP-7702 delegated EOA (delegate ${ethers.getAddress("0x" + code.slice(8, 48))}), not a Safe`);
    return;
  }
  if (!declared.proxyCodeHashes.some((h) => same(h, ethers.keccak256(code)))) {
    problems.push(`governor code hash ${ethers.keccak256(code)} is not a declared SafeProxy code hash`);
    return;
  }
  const slots = safeSlots(ethers);
  const singleton = await readAddressSlot(ethers, provider, account, slots.singleton, blockTag);
  if (!declared.singletons.some((s) => same(s, singleton))) {
    problems.push(`Safe singleton ${singleton} is not one of the declared singletons`);
    return;
  }
  if ((await provider.getCode(singleton, blockTag)) === "0x") {
    problems.push(`Safe singleton ${singleton} has no code`);
    return;
  }

  const safe = new ethers.Contract(account, SAFE_ABI, provider);
  const version = await safe.VERSION(at);
  info.push(`Safe ${version}, singleton ${singleton}`);
  if (!versionAtLeast(version)) problems.push(`Safe version ${version} is older than 1.3.0 (transaction hash does not cover the chain id)`);

  const m = await safe.getThreshold(at);
  const owners = await safe.getOwners(at);
  info.push(`owners ${owners.join(", ")}`);
  if (threshold && (m !== BigInt(threshold.m) || owners.length !== threshold.n)) {
    problems.push(`Safe is ${m}-of-${owners.length}, manifest declares ${threshold.m}-of-${threshold.n}`);
  }

  const { modules, complete } = await enabledModules(safe, at);
  if (!complete) problems.push(`more than ${MAX_MODULE_PAGES * MODULE_PAGE_SIZE} modules enabled; list not read to the end`);
  for (const module of modules) {
    if (allowedModules.some((a) => same(a, module))) {
      info.push(`module ${module} enabled (declared in the manifest)`);
    } else {
      problems.push(`module ${module} is enabled and not declared; a module executes transactions without the owners' signatures`);
    }
  }

  const guard = await readAddressSlot(ethers, provider, account, slots.guard, blockTag);
  if (guard !== ethers.ZeroAddress) info.push(`transaction guard ${guard} is set`);
  const handler = await readAddressSlot(ethers, provider, account, slots.fallbackHandler, blockTag);
  if (handler !== ethers.ZeroAddress) info.push(`fallback handler ${handler} is set`);
}

/**
 * Returns one entry per manifest scope: { name, scopeId, governor, problems: string[], info: string[] }, where
 * `governor` is the registry's on-chain governor. An empty `problems` array means every check passed; `info`
 * reports facts a reviewer may want to see (version, owners, declared modules, guard, pending handover). Missing
 * manifest fields are problems, never skipped checks. Never throws for a wrong configuration; it reports it.
 * Every read is made at `blockTag` (a block number or tag; default "latest"); scripts/check-governor.js passes
 * the block that the manifest's finality tag resolves to.
 */
async function checkGovernors({ ethers, provider, manifest, blockTag = "latest" }) {
  const at = { blockTag };
  const c = manifest.contracts || {};
  const safeDecl = manifest.governorSafe || {};
  const declared = { singletons: safeDecl.singletons || [], proxyCodeHashes: safeDecl.proxyCodeHashes || [] };
  const registry = c.registry ? new ethers.Contract(c.registry, REGISTRY_ABI, provider) : null;
  const registryHasCode = registry !== null && (await provider.getCode(c.registry, blockTag)) !== "0x";
  const results = [];

  for (const scope of manifest.scopes || []) {
    const problems = [];
    const info = [];
    const result = { name: scope.name, scopeId: scope.scopeId, governor: null, problems, info };
    results.push(result);

    if (!registry) problems.push("manifest lacks contracts.registry");
    else if (!registryHasCode) problems.push("no contract at contracts.registry");
    if (declared.singletons.length === 0) problems.push("manifest lacks governorSafe.singletons");
    if (declared.proxyCodeHashes.length === 0) problems.push("manifest lacks governorSafe.proxyCodeHashes");
    if (!scope.scopeId) problems.push("manifest lacks the scope id");
    const threshold = parseThreshold(scope.governorThreshold);
    if (!scope.governorThreshold) problems.push("manifest lacks governorThreshold");
    else if (!threshold) problems.push(`governorThreshold ${scope.governorThreshold} is not m-of-n with 1 <= m <= n`);
    if (!registryHasCode || !scope.scopeId) continue;

    let onChain;
    try {
      onChain = await registry.scopes(scope.scopeId, at);
    } catch (e) {
      problems.push("contracts.registry does not answer scopes(bytes32); not a VerifiablePolicyRegistry");
      continue;
    }
    if (!onChain.exists) {
      problems.push("scope does not exist in the registry");
      continue;
    }
    result.governor = onChain.governor;
    if (!same(onChain.governor, scope.governor)) {
      // The checks below apply to the on-chain governor: it is the address that holds the power.
      problems.push(`registry governor ${onChain.governor} differs from the manifest governor ${scope.governor}`);
    }
    const pending = await registry.pendingGovernor(scope.scopeId, at);
    if (pending !== ethers.ZeroAddress) info.push(`governor handover to ${pending} is pending`);
    if (declared.singletons.length === 0 || declared.proxyCodeHashes.length === 0) continue;

    await checkSafe({
      ethers,
      provider,
      blockTag,
      account: onChain.governor,
      declared,
      threshold,
      allowedModules: scope.governorModules || [],
      problems,
      info,
    });
  }
  return results;
}

module.exports = { SENTINEL, DELEGATION_PREFIX, safeSlots, parseThreshold, versionAtLeast, enabledModules, checkGovernors };
