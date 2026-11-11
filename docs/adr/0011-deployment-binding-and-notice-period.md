# ADR-0011: Bind documents to their deployment, and add a notice period before a version takes effect

- Status: Proposed (for the M1 review; not implemented)
- Date: 2026-11-11

## Context

This record addresses two limits of the current design. The second is stated in the white paper (§6.2) and the threat model (T47). The first is new here: §6.3 presents same-id redeployment as a feature, and this record looks at what it leaves open. Both need a decision before the contracts are audited, because the contracts are not upgradeable and changing them means a new deployment.

**1. Nothing in a policy document says where it is authoritative.**
- The scope id is `keccak256(abi.encode(creator, name))` (INTERFACES I2). It does not include the chain id or the registry address. This is deliberate: after a defect, the same Safe re-creates its scopes on a new deployment under the same ids (white paper §6.3).
- The policy document (I1) names the scope and a version number, but no chain and no registry. The appeal document (I9) names only the scope.
- A Safe deployed with the same owners, threshold and salt has the same address on several chains. So the same scope id, and the same content hash, can then exist on more than one chain or registry.
- The chain itself is not the problem. From Safe v1.3.0 on, Safe transactions are signed over an EIP-712 domain that includes the chain id, so a governor transaction cannot be replayed on another chain. Older Safe versions do not include it, so a pilot should use v1.3.0 or later.
- The problem is interpretation. A document says nothing about which deployment, or which of several scopes with the same name in one registry (INTERFACES, scope discovery), it belongs to. Its `version` field is compared with the on-chain version number only if a verifier runs `vpr check-onchain` with the on-chain values; nothing makes that comparison part of the required checks.
- Verifiers resolve this today only by pinning the chain id and addresses from the deployment manifest (I11).

**2. A version takes effect in the block that appends it.**
- A threshold of signers can change the policy in force at once (adversary A2). The minority signer, the reviewer and the public see the change only after it applies.
- Expiry and appeals bound the damage afterwards, but nothing gives time to object beforehand.
- Some changes cannot wait. GOVERNANCE defines an emergency unblock (reason code 6) and an emergency block for an active threat (reason code 4), both with a short validity.
- The contract cannot tell whether a version adds blocks or removes them, because it sees only a hash.

## Decision

### Deployment binding: in the documents, not in the scope id

- The scope id formula is unchanged, so a redeployment keeps its ids.
- The next policy format (format 2) and the next appeal format (format 4) add a required `deployment` object: `{chain_id, registry, scope_id}`. It names the chain id, the registry address and the scope id the document is meant for. The scope id is needed because the name alone does not identify a scope: anyone can create the same name under another address in the same registry. Because the object is part of the canonical document, the content hash binds it. After a redeployment by the same Safe, only `registry` changes.
- Tools refuse a document whose `deployment` does not match the manifest they verify against. The comparison of a policy document's `version` with the on-chain version number that carries its hash, which `vpr check-onchain` already offers, becomes a required check of the sync daemon and the dashboard.
- These checks run off-chain; the registry still stores only the hash. A document for one deployment can therefore still be published on another, but every verifier that follows I11 rejects it there. The check is public and needs no key, like the other off-chain checks.

### Notice period: in the registry, with a bounded emergency path

All durations below (72 hours, 30 days, 7 days) are placeholders to be set at the M1 review.

- **Per-scope notice.** Each scope gets a `minNotice`, set at creation (proposed default: 72 hours). It can be increased but never decreased, so a captured governor cannot remove it. It is capped at `MAX_NOTICE` (proposed: 30 days), so it cannot be raised until no ordinary version can ever take effect.
- **Effective time.** `publishPolicy` takes an `effectiveAt`. The version is appended at once, so it is public at once, but it is not in force before `effectiveAt`. For an ordinary version, `effectiveAt` must satisfy three bounds:
  - it is at least `block.timestamp + minNotice`;
  - it is at most `block.timestamp + MAX_NOTICE`, so a version cannot be scheduled years ahead;
  - it is not earlier than the `effectiveAt` of any earlier ordinary version, so ordinary versions take effect in the order they were published.
- **Validity from effect.** `expiresAt = effectiveAt + validity`, so the notice does not consume validity. Every version therefore expires at most `MAX_NOTICE + MAX_VALIDITY_CAP` after it is published, and P4 is restated with that bound.
- **Which version is in force.** At time τ, the candidate is the version with the greatest `(effectiveAt, version number)` among those with `effectiveAt ≤ τ`. It is in force while τ < its `expiresAt`. Otherwise no version is in force and the scope falls back to protective categories, as when a version expires today; an older version never comes back into force.
- **Superseding and reading.** `currentPolicy` returns the version in force and the next pending version, if any. A pending version is superseded by publishing another with the same or a later `effectiveAt`; nothing is deleted.
- **Emergency path.** An emergency version is one with reason code 4 or 6 and `effectiveAt = block.timestamp`. It is allowed under two bounds enforced on-chain:
  - its validity is at most 7 days;
  - its `effectiveAt` is at least 30 days after that of the scope's previous emergency version.

  An emergency version takes effect at once, ahead of any pending ordinary version. Once that pending version's `effectiveAt` arrives, the pending version is in force instead. If the emergency version expires first, no version is in force until then.

  An abusive governor can therefore impose a change without notice for at most 7 days in any 30. That window is public, carries a reason code, and can be appealed. Accepted appeals (reason code 3) are not emergencies: a version that accepts an appeal waits `minNotice` like any ordinary version.
- **What stays instant.** Only policy versions are delayed. `setIssuer`, the governor handover, `setPublisher` and `correctRoot` still take effect in the block that contains them; T47 keeps them listed as instant.
- **What changes.** INTERFACES I2, the invariants (`currentPolicyInForce`, `boundedDuration`) and the symbolic checks are revised with the change. P4 is restated over `effectiveAt`.

## Consequences

- **Objection becomes possible.** The minority signer, the reviewer and the public get `minNotice` to object, file appeals or prepare the resolver before a non-emergency version applies. A2 moves from "detected after the fact" to "visible before it takes effect", except within the bounded emergency window.
- **Changes are slower.** Every ordinary change and every renewal must be published at least `minNotice` before it is needed. Renewals already have to be timed against expiry and finality latency (white paper §3.2), so this adds a fixed margin, not a new kind of constraint.
- **Emergencies are bounded, not trusted.** The emergency path is limited by duration and frequency, not by trusting the reason code. The chain cannot check that an "emergency" is genuine, and the ADR does not pretend it can.
- **Redeployment changes the documents, not the ids.** Binding the documents to a deployment means a redeployment needs re-issued documents (new hashes), but scope ids stay the same. Documents in format 1 remain valid under their existing rules.
- **Verifiers do more work.** The resolver's sync daemon (VPR-015) and the dashboard must read `effectiveAt` and pending versions, and tools must check `deployment` and `version`.
- **New contracts.** The notice period would need new contracts and an audit scope that includes them; the deployment binding needs new document formats and tool checks only. ADR-0010 already requires a redeployment at M4. Taking this record before the M3 audit would add a second redeployment, which the M1 review should weigh against deferring both changes to a single new deployment.

## Maintainer's recommendation for the M1 review

Recorded 2026-11-11. The status stays Proposed until the M1 review with the pilot partners.

- **Durations.** Keep the proposed values as the starting point: `minNotice` 72 hours by default, `MAX_NOTICE` 30 days, emergency validity of at most 7 days, and at least 30 days between emergencies. They match the existing 7-day emergency validity in GOVERNANCE and leave a working week to object. The pilot's charter may raise `minNotice` but should not lower it.
- **Sequencing.** Implement both decisions before the M3 audit, so that the audited contracts are the ones that would be deployed. Bring forward the registry part of ADR-0010 (the `catRoot` and `unitRoot` fields, VPR-058) into the same new registry, so that one redeployment carries both changes and M4 adds only the verifier contract. The cost is a larger M2–M3 scope. The benefit is that the M3 audit covers the registry that M4 relies on, and no deployment is audited only to be replaced.

## Alternatives considered

- **Scope id over the chain id and registry address** (`keccak256(abi.encode(block.chainid, address(this), creator, name))`, an EIP-712-style domain). It binds on-chain, but the id changes on every redeployment, which breaks the recovery path of §6.3 and every pinned manifest. Rejected. A document-level binding gives verifiers the same information without that cost.
- **A timelock on the governor Safe** (for example a delay module). It needs no contract change. But it delays every governor transaction, including emergencies and handovers, and it is invisible to the registry: verifiers would have to inspect the Safe's modules to know whether a notice applies. Kept as an option for charters that want it in addition, not as the mechanism.
- **An on-chain veto by a minority signer during the notice.** It would contradict the *m*-of-*n* threshold that the charter sets, and one signer could block renewals. Rejected. The notice gives time to object through appeals and the charter, not a veto.
- **No emergency path.** It is simpler, but it would delay unblocking an educational resource or blocking an active malware campaign by `minNotice`, which GOVERNANCE treats as unacceptable. Rejected.
- **Exempting emergencies by reason code alone, with no bound.** That would let any change be labelled an emergency. Rejected in favour of the duration and frequency bounds above.
