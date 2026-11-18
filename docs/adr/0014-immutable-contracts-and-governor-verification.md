# ADR-0014: Immutable contracts, and a governor verified as a Safe off-chain

- Status: Accepted for §1 and §2 (immutability and off-chain governor verification, with `check-governor.js` implemented); Proposed for §3 (a handover delay in the next registry, for the M1 review)
- Date: 2026-11-18

## Context

Two questions were raised in review.

**Upgradeability.** Should the contracts be upgradeable, and if so, who holds the right to upgrade them? Earlier records (ADR-0010, ADR-0011) assume they are not, but no record decides it.

**What the governor is.** Can the contract require that a governor be a contract, specifically a Safe, and not an externally owned account (EOA)? And how is a governor replaced?

The registry accepts any address as governor:
- `createScope` makes the caller the governor;
- `proposeGovernor` and `acceptGovernor` hand a scope to another address in two steps;
- the handover takes effect in the block that contains `acceptGovernor` (threat model T47).

The white paper's properties assume a Safe with an *m*-of-*n* threshold (P3), but nothing checks that assumption. The deployment manifest declares `governorThreshold` "checked by verifiers against the Safe itself", but no verifier implemented that check until now.

## Decision

### 1. The contracts stay immutable

The registry and the anchor have no proxy and no administrator. A defect is fixed by a new deployment, on which each governor re-creates its scopes under the same ids (white paper §6.3) and verifiers update the manifest.

The reason is that an upgrade key is a governor above every governor. Whoever can replace the implementation can rewrite:
- the history of versions (P2);
- the expiry bound (P4);
- the appeal state machine (P5);
- the anchored roots (P7).

They can do so for every scope at once, without any scope's threshold. The properties would then hold only until that key decided otherwise, and every verifier would also have to monitor the upgrade path.

Planned changes are batched into as few redeployments as possible (ADR-0011's recommendation: one redeployment before the M3 audit).

### 2. The governor is verified off-chain, against the chain

The contract does not test whether a governor is a contract. Such a test would give false assurance, for three reasons:
- **Delegated EOAs have code.** EIP-7702 has been active on OP Mainnet since the Isthmus upgrade (9 May 2025). An EOA with a delegation has 23 bytes of code (`0xef0100 ‖ address`), so `code.length > 0` accepts an EOA.
- **Constructors have no code.** A contract has no code during its constructor, so a factory that creates a scope from a constructor would be refused.
- **A contract is not a Safe.** A one-signer wrapper passes the test as easily as a 3-of-5 Safe.

Instead, the deployment manifest declares, for each scope, the governor, its threshold *m*-of-*n* and any modules it may enable. For the deployment as a whole, it declares the Safe singletons and the SafeProxy runtime code hashes it accepts (`governorSafe`, INTERFACES I11). `contracts/scripts/check-governor.js` checks the declaration against the chain at the manifest's finality tag. It is read-only and needs no key:
- **Registry.** The registry's governor for the scope is the declared address.
- **Code.** The governor has code, and that code is not an EIP-7702 delegation.
- **Safe.** The governor's runtime code hashes to a declared SafeProxy code hash, and its singleton (storage slot 0) is a declared one, at version 1.3.0 or later. Earlier versions do not sign over the chain id. Because the proxy forwards every call to that singleton, the answers below come from the declared singleton's code and not from code the governor chose.
- **Threshold.** The threshold and the number of owners match the declaration.
- **Modules.** No module is enabled unless the manifest declares it, because a module executes transactions without the owners' signatures and so bypasses the threshold. A transaction guard, the fallback handler and a pending handover are reported as information.
- **Finality.** Every value is read at the block that the manifest's finality tag resolves to.

The check has stated limits. It holds for the block it reads. It does not check who the owners are. It sees the owners and modules that the Safe lists, so an entry written by a delegatecall without being linked into the list would be missed. It is tested against a real Safe 1.4.1, whose artifacts are checked against the code hashes of the canonical deployments, in `contracts/test/GovernorCheck.test.js`. Safe 1.3.0 is covered only for its different module paging.

The dashboard (VPR-021) and the manifest alerts (VPR-049) run this check, as they do for `GovernorChanged` and changes of Safe owners or threshold.

Replacing the governor is already implemented. The current governor calls `proposeGovernor`, and the new one calls `acceptGovernor`; proposing `address(0)` cancels a pending proposal. Acceptance proves that the new governor can act: a Safe must reach its own threshold to accept. Owners are rotated inside the Safe (`swapOwner`, `changeThreshold`), not by handing the scope over.

### 3. Proposed: a delay before a handover takes effect

In the next registry (together with ADR-0010 and ADR-0011), `acceptGovernor` succeeds only once the scope's `minNotice` (ADR-0011) has passed since `proposeGovernor`. The proposal is public at once, and the current governor can cancel it until then.

A legitimate emergency, such as a compromised signer, is handled inside the Safe by rotating owners, so it does not need an instant handover. A handover moves the whole scope to another party, which is exactly the change the public should see before it happens.

## Consequences

- **No privileged key above the scopes.** Verifiers check one thing per scope, its governor, and not an upgrade path as well.
- **Fixes cost a redeployment.** Scope ids survive it; documents need re-issuing only under ADR-0011's deployment binding. A redeployment also needs a new audit scope.
- **The Safe assumption is checked, not assumed.** A scope whose governor is an EOA, a delegated EOA, a 1-of-*n* Safe that declares more, or a Safe with an undeclared module fails the check publicly. It is not refused on-chain: the registry stays general (ADR-0013), and a scope's verifiers decide what they accept.
- **The check is only as current as its last run.** A Safe's configuration can change between runs. That is why the dashboard alerts on Safe events and does not rely on periodic checks alone.

## Alternatives considered

- **Upgradeable proxy (UUPS or transparent) administered by a protocol Safe with a timelock.** Fixes are faster. It adds a key above all scopes, more audit surface, and a path every verifier must watch. Rejected for the audited core.
- **Upgrade opt-in per scope** (each governor chooses an implementation). There is no common key, but verification fragments: two scopes in "the same registry" could follow different rules. Rejected.
- **An on-chain `code.length` or `extcodehash` check.** False assurance, for the reasons in §2. Pinning the governor's code hash on-chain to a known Safe proxy would fix one factory and version in an immutable contract, and it would still not check the threshold or modules, which live in storage and can change. Rejected in favour of the off-chain check, which uses the same code hash but takes the accepted hashes from the manifest.
- **Safe owner and threshold checks on-chain at each call.** It ties the registry to one wallet implementation, adds gas to every call, and still misses modules added later. Rejected.
