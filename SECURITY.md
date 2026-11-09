# Security policy

## Status

The project is a research prototype (v0.3 preparation). The contracts are **not audited**, have not been formally verified and are not deployed to any network other than local test chains. No independent security review has taken place. An external audit of the registry, the anchor and the resolver configuration is planned before mainnet deployment ([ROADMAP](docs/ROADMAP.md), milestone M3, Gate C). The threat model is in [docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md).

## Reporting a vulnerability

Please report vulnerabilities privately, never in a public issue or pull request.

- Preferred: GitHub private vulnerability reporting, from the **Security** tab of this repository ("Report a vulnerability").
- Alternative: email dpg@xcapit.com with the subject `[VPR security]`.

Include what you found, the affected component and version or commit, steps to reproduce and the impact you expect. If the issue could expose personal data or let someone bypass protection for children, say so in the first line so we can prioritise it.

We will:

1. acknowledge your report within 3 working days;
2. give a first assessment within 10 working days;
3. agree a disclosure date with you (default: 90 days, sooner once a fix is deployed);
4. credit you in the advisory unless you prefer otherwise.

## Scope

In scope:

- `contracts/`: access control, appeal state machine, expiry checks, Merkle verification;
- `tools/`: policy hashing and validation, RPZ compilation and zone evaluation, aggregation with small-cell suppression (including any leak of suppressed cells), Merkle proofs, the toolkit API and CLI;
- `examples/e2e/`: the demonstrator, including any way it could publish data it should not;
- `deploy/`: reference resolver configuration (for example settings that would leak query data);
- `schemas/`: issues that would let one role issue an attestation reserved for another.

Out of scope: third-party services (Safe, EAS, OP Mainnet, Unbound) unless the problem comes from how this project uses them; findings that need a compromised governor key; volumetric denial of service.

## Data we hold

The resolver processes client addresses and queried names transiently to answer queries, but nothing identifying is retained, exported or published by design ([privacy statement](docs/PRIVACY_STATEMENT.md)). If you find personal data anywhere in this repository, its history or a published dataset, report it as a vulnerability.
