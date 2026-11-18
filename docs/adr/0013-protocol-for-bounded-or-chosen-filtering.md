# ADR-0013: A protocol for filtering in bounded networks or chosen by the user; schools are the first deployment

- Status: Accepted (supersedes ADR-0006; keeps its exclusion of ISP-wide and national blocking)
- Date: 2026-11-18

## Context

ADR-0006 limited the project to bounded networks with an accountable governor, such as schools, libraries, municipal Wi-Fi and NGO networks. It declined features aimed at ISP-wide or national blocking. The exclusion holds, but the positive scope is narrower than the mechanism.

None of the mechanism is specific to schools:
- versioned policy documents committed by hash, each with a reason;
- expiry bounded per scope, and appeals;
- a threshold governor;
- attestations from issuers other than the operator;
- verifiable aggregate releases.

The verification toolkit is already independent of the use case (ADR-0009).

Other parties apply blocklists today, and their users cannot see what is blocked, who decided it or how to contest it. Examples:
- wallets that warn about or refuse phishing domains and drainer contracts;
- dApp front ends that block addresses or domains;
- protective DNS resolvers that users choose for themselves.

These lists are generally maintained by one party, change without a public record, and have no expiry or reasoned appeal. They have the same accountability gap that VPR addresses for school filtering.

## Decision

**The protocol serves two kinds of policy:**
- **Bounded networks.** A policy applied inside a bounded network by an accountable governor: schools, libraries, municipal Wi-Fi, health centres, NGO networks.
- **User-chosen software or services.** A policy applied by software or a service that the affected user chooses and can stop using: a wallet, a browser extension, a dApp front end's own lists, or a public resolver the user configures.

**Out of scope, as in ADR-0006:** policies imposed at the level of an internet service provider or a nation, on users who cannot choose another resolver or provider. The project does not add features aimed at them, and pull requests that do are declined.

**Schools are the first deployment.** The Giga pilot proposal ([PILOT_READINESS](../giga/PILOT_READINESS.md)) remains the reference deployment and the first use case. Other uses are integration targets: none of them is a partner, deployment or commitment.

**What is shared across uses**, and is implemented today:
- the registry and anchor contracts;
- the EAS schemas;
- the canonical document hashing;
- `vpr.toolkit` (stable API v1) and the `vpr` CLI.

A scope is a policy of one governor. A wallet vendor, a dApp or a resolver operator creates its own scopes in the same registry, with its own Safe.

**What a new use needs**, which is not implemented and is tracked in the backlog:
- **A verification library for clients.** A TypeScript library (VPR-073) that reads `currentPolicy`, fetches the document, checks its content hash, the expiry and the rules digest (ADR-0012), and evaluates a name locally.
- **A reference integration in a wallet** (VPR-074).
- **Policy subjects other than domain names.** Contract addresses, for example, need a new policy format with its own ADR (VPR-075). Policy format 1 lists domain names only.

**Clients must evaluate locally.** A client that checks a name must download the policy and evaluate it on the device. It must not send each queried name to a server. The queried name is personal data in the same way that a DNS query is (white paper §5.1).

## Consequences

- **Wider reuse, same exclusion.** Builders outside education can adopt the registry without a fork. The line against ISP-wide and national blocking is unchanged and is restated here.
- **Enforcement evidence differs by use.**
  - In a network, the independent reviewer attests that the resolver enforces the policy (P6).
  - In client software, enforcement is the open-source client itself. `VPR.IndependentTest.v1` is defined for networks; whether clients need an attestation of their own is open and is not decided here.
  - Users can see the policy and appeal it in both cases.
- **Governance stays per scope.** Each adopter brings its own governor and charter. A wallet vendor's 1-of-1 Safe is visible in the registry, but it is not the threshold governance that the school charter requires. Verifiers must read each scope's governor and its declared configuration (deployment manifest, VPR-049), and must not assume the school charter.
- **More surface for misuse.** A user-chosen service can still be used to filter speech. The protocol does not prevent that. It makes the policy public, expiring and contestable, and the choice of service stays with the user.
- **Documentation.** The README, the white paper (§3.5 and §11.3), the roadmap and the claims ledger describe VPR as a protocol whose first deployment is school connectivity. Phase 1 milestones and payment shares are unchanged.

## Alternatives considered

- **Keep ADR-0006 unchanged.** Clear, but it leaves out user-chosen software, where the same accountability gap exists and the risk to population-wide information rights is lower, because the user can leave. Rejected.
- **Open the scope to any resolver, including ISP and national resolvers.** That would make the project a tool for unaccountable population-wide blocking, which ADR-0006 exists to prevent. Rejected.
- **A separate project for wallets and dApps.** That would fork the registry, the schemas and the verification rules, and verifiers would have two systems to check. Rejected: one registry with per-scope governors serves both.
