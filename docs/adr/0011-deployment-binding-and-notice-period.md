# ADR-0011: Bind documents to their deployment, and add a notice period before a version takes effect

- Status: Proposed (for the M1 review; not implemented)
- Date: 2026-11-11

## Context

Two limits of the current design are stated in the white paper (§6.2, §6.3) and the threat model (T47). Both need a decision before the contracts are audited, because the contracts are not upgradeable and either change means a new deployment.

**1. Nothing in a policy document says where it is authoritative.**
- The scope id is `keccak256(abi.encode(creator, name))` (INTERFACES I2). It does not include the chain id or the registry address. This is deliberate: after a defect, the same Safe re-creates its scopes on a new deployment under the same ids (white paper §6.3).
- The policy document (I1) names the scope and a version number, but no chain and no registry. The appeal document (I9) names only the scope.
- A Safe deployed with the same owners, threshold and salt has the same address on several chains. So the same scope id, and the same content hash, can then exist on more than one chain or registry.
- The chain itself is not the problem. Safe transactions are signed over an EIP-712 domain that includes the chain id, so a governor transaction cannot be replayed on another chain. The problem is interpretation: a document says nothing about which deployment is authoritative, and its `version` field is never checked against the on-chain version number.
- Verifiers resolve this today only by pinning the chain id and addresses from the deployment manifest (I11).

**2. A version takes effect in the block that appends it.**
- A threshold of signers can change the policy in force at once (adversary A2). The minority signer, the reviewer and the public see the change only after it applies.
- Expiry and appeals bound the damage afterwards, but nothing gives time to object beforehand.
- Some changes cannot wait. GOVERNANCE defines an emergency unblock (reason code 6) and an emergency block for an active threat (reason code 4), both with a short validity.
- The contract cannot tell whether a version adds blocks or removes them, because it sees only a hash.

## Decision

### Deployment binding: in the documents, not in the scope id

- The scope id formula is unchanged, so a redeployment keeps its ids.
- The next policy format (format 2) and the next appeal format (format 4) add a required `deployment` object: `{chain_id, registry}`, the chain id and the registry address that the document is meant for. Because it is part of the canonical document, the content hash binds it.
- Tools refuse a document whose `deployment` does not match the manifest they verify against. They also refuse a policy document whose `version` differs from the on-chain version number that carries its hash.
- These checks run off-chain; the registry still stores only the hash. A document for one deployment can therefore still be published on another, but every verifier that follows I11 rejects it there. The check is public and needs no key, like the other off-chain checks.

### Notice period: in the registry, with a bounded emergency path

- **Per-scope notice.** Each scope gets a `minNotice`, set at creation (proposed default: 72 hours). It can only be increased, so a captured governor cannot remove it.
- **Effective time.** `publishPolicy` takes an `effectiveAt`, with `effectiveAt ≥ block.timestamp + minNotice`. The version is appended at once, so it is public at once, but it is not in force before `effectiveAt`.
- **Validity from effect.** `expiresAt = effectiveAt + validity`, so the notice does not consume validity.
- **Which version is in force.** At time τ it is the latest version with `effectiveAt ≤ τ`, while τ < its `expiresAt`. `currentPolicy` returns it and also returns the next pending version, if any. A pending version can be superseded before it takes effect by publishing another one; nothing is deleted.
- **Emergency path.** A version with reason code 4 or 6 may take effect immediately, under three bounds enforced on-chain:
  - its validity is at most 7 days;
  - a scope can have at most one such version per 30 days;
  - the next non-emergency version must observe the full notice.

  An abusive governor can therefore impose an unnoticed change for at most 7 days in any 30. That window is public, carries a reason code, and can be appealed.
- **What changes.** INTERFACES I2, the invariants (`currentPolicyInForce`, `boundedDuration`) and the symbolic checks are revised with the change. P4 is restated over `effectiveAt`.

## Consequences

- **Objection becomes possible.** The minority signer, the reviewer and the public get `minNotice` to object, file appeals or prepare the resolver before a non-emergency version applies. A2 moves from "detected after the fact" to "visible before it takes effect", except within the bounded emergency window.
- **Changes are slower.** Every ordinary change and every renewal must be published at least `minNotice` before it is needed. Renewals already have to be timed against expiry and finality latency (white paper §3.2), so this adds a fixed margin, not a new kind of constraint.
- **Emergencies are bounded, not trusted.** The emergency path is limited by duration and frequency, not by trusting the reason code. The chain cannot check that an "emergency" is genuine, and the ADR does not pretend it can.
- **Redeployment changes the documents, not the ids.** Binding the documents to a deployment means a redeployment needs re-issued documents (new hashes), but scope ids stay the same. Documents in format 1 remain valid under their existing rules.
- **Verifiers do more work.** The resolver's sync daemon (VPR-015) and the dashboard must read `effectiveAt` and pending versions, and tools must check `deployment` and `version`.
- **New contracts.** Both decisions need new contracts and a new audit scope, and are planned before M3.

## Alternatives considered

- **Scope id over the chain id and registry address** (`keccak256(abi.encode(block.chainid, address(this), creator, name))`, an EIP-712-style domain). It binds on-chain, but the id changes on every redeployment, which breaks the recovery path of §6.3 and every pinned manifest. Rejected. A document-level binding gives verifiers the same information without that cost.
- **A timelock on the governor Safe** (for example a delay module). It needs no contract change. But it delays every governor transaction, including emergencies and handovers, and it is invisible to the registry: verifiers would have to inspect the Safe's modules to know whether a notice applies. Kept as an option for charters that want it in addition, not as the mechanism.
- **An on-chain veto by a minority signer during the notice.** It would contradict the *m*-of-*n* threshold that the charter sets, and one signer could block renewals. Rejected. The notice gives time to object through appeals and the charter, not a veto.
- **No emergency path.** It is simpler, but it would delay unblocking an educational resource or blocking an active malware campaign by `minNotice`, which GOVERNANCE treats as unacceptable. Rejected.
- **Exempting emergencies by reason code alone, with no bound.** That would let any change be labelled an emergency. Rejected in favour of the duration and frequency bounds above.
