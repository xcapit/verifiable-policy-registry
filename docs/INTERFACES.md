# Interfaces

*CC BY 4.0 · Policy format 1, dataset format 2, appeal format 2 · Applies to the contracts in `contracts/src/` and the `vpr` tools 0.2.x*

This document specifies every boundary between the components described in [ARCHITECTURE.md](ARCHITECTURE.md): what each side sends, in which format, and what the receiver must check. If two components are built by different teams, this is the contract between them. Anything marked **planned** is not implemented yet and links to its backlog item.

## Map

```mermaid
flowchart LR
  AUTH[Policy authors] -- "I1 policy document" --> GOV[Governor Safe]
  GOV -- "I2 registry ABI" --> REG[(VerifiablePolicyRegistry)]
  REG -- "I3 PolicyPublished event" --> SYNC[Sync daemon]
  SYNC -- "I4 RPZ zone" --> RES[Resolver]
  RES -- "I5 block events" --> AGG[Aggregator]
  AGG -- "I6 public dataset" --> PUB[Public storage]
  AGG -- "I7 anchor ABI" --> ANC[(MetricsAnchor)]
  OPS[Operator / reviewer / auditor] -- "I8 EAS attestations" --> EAS[(EAS)]
  BP[Block page] -- "I9 appeal document" --> REG
  REG & ANC & EAS & PUB --> DASH[Dashboard / any verifier]
```

## Common conventions

| Item | Rule |
| --- | --- |
| Hash function | keccak256 (Ethereum), not NIST SHA3-256 |
| Hex encoding | `0x` prefix, lowercase, 32 bytes = 64 hex characters |
| Scope name | UTF-8 string `<programme>:<country>:<profile>`, for example `giga:AR:primary`. Country is ISO 3166-1 alpha-2 (`XX` in examples) |
| Scope id | `bytes32 scopeId = keccak256(utf8(scope))` |
| School id | Public Giga school identifier (or the equivalent public id of the network). Never a personal identifier |
| Dates | `YYYY-MM-DD`, UTC, in documents and datasets |
| Day number | On-chain `uint32 day` = whole days since 1970-01-01 UTC. `2026-11-01` is day `20758` |
| Times | `uint64` Unix seconds on-chain |
| Domains | Lowercase ASCII, no trailing dot; internationalised names in punycode (`xn--`) |
| Reason codes | Table in [GOVERNANCE.md](GOVERNANCE.md#reason-codes), shared by contracts and documents |

## I1 · Policy document

Producer: policy authors (operator drafts, governor signers approve). Consumers: `vpr` tools, sync daemon, dashboard, the public.

**Format.** YAML (or JSON) validated by [`schemas/policy.schema.json`](../schemas/policy.schema.json). Example: [`policies/example-primary.yaml`](../policies/example-primary.yaml).

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `scope` | string | yes | Scope name; must match the on-chain scope |
| `version` | integer ≥ 1 | yes | Document version; should equal the on-chain version it is published as |
| `profile` | `primary` \| `secondary` \| `teachers` | yes | Filtering profile |
| `categories` | list of strings | yes | Category feeds applied (mapped to ITU COP categories) |
| `local_blocks` | list of `{domain, reason}` | yes | Extra blocks for this scope; every entry states why |
| `exceptions` | list of `{domain, reason}` | yes | Never blocked when a feed or local block lists the same domain; a feed entry for a subdomain of an exception stays blocked (exact-match RPZ semantics); an exception that equals or covers a restricted entry is refused at compilation; every entry states why |
| `valid_days` | integer | recommended | Intended validity; must be ≤ the scope `maxValidity` |
| `reason_code` | integer | recommended | Same value passed to `publishPolicy` |
| `threat_feeds` | list of `{provider, version}` | optional | Third-party feeds by reference, never copied |
| `restricted_list_hash` | `0x` hex or `null` | optional | Commitment to a restricted list (see below) |

Validation rules enforced by `vpr.policy.validate`, identical to the JSON schema: required keys present and no unknown keys; scope, version, profile, categories (unique), `valid_days`, `reason_code` and `threat_feeds` well formed; domains valid; every block and exception has exactly a domain and a non-empty reason; no domain is both blocked and excepted; `restricted_list_hash` well formed.

**Canonical form and `contentHash`.**

1. Parse the document and validate it. Validation normalises domains (lowercase, trailing dot removed).
2. Serialise as JSON with keys sorted, separators `,` and `:` without spaces, UTF-8, non-ASCII characters kept as is (Python: `json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`).
3. `contentHash = keccak256(canonical_bytes)`.

Comments and key order in the YAML do not affect the hash; values do. `vpr policy-hash <file>` prints the `scopeId` and `contentHash`.

**Restricted list commitment.** `restricted_list_hash = keccak256(utf8(join("\n", sorted(unique(normalised domains)))))`. The same value goes in the document and in the `restrictedListHash` argument of `publishPolicy` (`0x00…00` when there is none).

## I2 · `VerifiablePolicyRegistry` ABI

Source: [`contracts/src/VerifiablePolicyRegistry.sol`](../contracts/src/VerifiablePolicyRegistry.sol).

| Function | Caller | Effect | Reverts |
| --- | --- | --- | --- |
| `createScope(bytes32 scopeId, address governor, uint64 maxValidity)` | the governor itself | Creates a scope | `ScopeAlreadyExists`, `ZeroAddress`, `NotGovernor`, `InvalidValidity` |
| `setGovernor(bytes32 scopeId, address newGovernor)` | governor | Rotates the governor | `UnknownScope`, `NotGovernor`, `ZeroAddress` |
| `setIssuer(bytes32 scopeId, address issuer, Role role)` | governor | Grants, changes or revokes (`Role.None`) the attestation role of an address | `UnknownScope`, `NotGovernor`, `ZeroAddress` |
| `publishPolicy(bytes32 scopeId, bytes32 contentHash, bytes32 restrictedListHash, string uri, uint16 reasonCode, uint64 validity, bytes32 resolvesAppeal) → uint256 version` | governor | Appends a version (1-based); optionally accepts an appeal, recording `contentHash` as its resolution | `UnknownScope`, `NotGovernor`, `EmptyContentHash`, `InvalidValidity`, `AppealNotOpen`, `AppealScopeMismatch` |
| `fileAppeal(bytes32 scopeId, bytes32 documentHash) → bytes32 appealId` | anyone | Opens an appeal for the hash of an appeal document (I9); a rejected document can be filed again in a new round | `UnknownScope`, `EmptyDocumentHash`, `AppealAlreadyExists` |
| `rejectAppeal(bytes32 appealId, bytes32 reasonHash)` | governor of the appeal's scope | Closes an appeal as rejected, with the hash of a reasoned decision published off-chain | `AppealNotOpen`, `NotGovernor`, `EmptyReason` |
| `appealIdOf(bytes32 scopeId, bytes32 documentHash, uint32 round) → bytes32` | pure | `keccak256(abi.encode(scopeId, documentHash, round))` | none |
| `currentPolicy(bytes32 scopeId) → (uint256 version, PolicyVersion policy, bool inForce)` | view | Latest version; `inForce = block.timestamp < expiresAt` | none |
| `getVersion(bytes32 scopeId, uint256 version) → PolicyVersion` | view | A specific version | panics on out-of-range |
| `versionCount(bytes32 scopeId) → uint256` | view | Number of versions | none |
| `scopes(bytes32) → (address governor, uint64 maxValidity, bool exists)` | view | Scope record | none |
| `issuerRole(bytes32 scopeId, address) → Role` | view | `0 None, 1 Operator, 2 Reviewer, 3 Auditor`; one role per address per scope | none |
| `appeals(bytes32) → (bytes32 scopeId, uint8 status, uint32 round, uint64 filedAt, bytes32 documentHash, bytes32 resolutionHash)` | view | Appeal record; status `0 None, 1 Open, 2 Accepted, 3 Rejected` | none |
| `appealRounds(bytes32 key) → uint32` | view | Latest round for `key = keccak256(abi.encode(scopeId, documentHash))` | none |

`PolicyVersion = (bytes32 contentHash, bytes32 restrictedListHash, string uri, uint16 reasonCode, uint64 publishedAt, uint64 expiresAt, bytes32 resolvesAppeal)`.

Events: `ScopeCreated(scopeId, governor, maxValidity)`, `GovernorChanged(scopeId, previousGovernor, newGovernor)`, `IssuerSet(scopeId, issuer, role)`, `PolicyPublished(scopeId, version, contentHash, restrictedListHash, uri, reasonCode, expiresAt, resolvesAppeal)`, `AppealFiled(appealId, scopeId, documentHash, round)`, `AppealResolved(appealId, accepted, resolutionHash)`.

Invariants: versions are append-only; every version expires; an appeal moves only `Open → Accepted` or `Open → Rejected`; a document has at most one open or accepted round; no caller-supplied free text is stored through appeals (the policy `uri` is written by the governor only).

**Scope discovery.** Scope names are not authenticated by the contract: anyone who controls an address can create a scope under any unused name with itself as governor. Verifiers therefore never trust a scope by its name. They pin, from a deployment manifest published by the partners (planned, VPR-049), the chain id, the registry and anchor addresses, the scope id and the expected governor, and they alert on `GovernorChanged` and on changes to the Safe's owners or threshold.

## I3 · Registry → sync daemon (planned, [VPR-015](BACKLOG.md))

The daemon subscribes to `PolicyPublished` for its scope, then:

1. fetches the document at `uri`;
2. recomputes the canonical `contentHash` (I1) and **refuses** the document on mismatch, keeping the previous zone;
3. checks `inForce` through `currentPolicy`; if the version is expired, applies the fallback defined in the scope charter;
4. compiles the zone (I4) and reloads the resolver;
5. logs only scope, version and hash, never query data.

## I4 · RPZ zone (tools → resolver)

Produced by `vpr compile-rpz`. Standard Response Policy Zone usable by Unbound or PowerDNS. Reference loader: [`deploy/unbound/rpz.conf`](../deploy/unbound/rpz.conf).

- The first two comment lines identify the source, so a reviewer can link a running zone to an on-chain version:
  ```
  ; RPZ generated by vpr for scope <scope> version <version>
  ; policy content hash 0x<contentHash>
  ```
- Exceptions: `<domain> CNAME rpz-passthru.` and `*.<domain> CNAME rpz-passthru.`
- Blocks: `<domain> CNAME <block-page>.` (or `CNAME .` for NXDOMAIN), plus the wildcard. A comment states the source (`category:<name>` or `local`). Restricted entries carry no comment.
- SOA serial: `YYYYMMDDHH` in UTC.

## I5 · Block events (resolver exporter → aggregator)

Exporter is planned ([VPR-016](BACKLOG.md)); the aggregator is implemented.

CSV with header `<unit>,day,category` (`<unit>` is `school_id` or `unit_id`), one row per event; `metrics.read_events` rejects any other column. These three fields are the **only** ones allowed: no IP address, no device identifier, no queried name, no timestamp finer than a day. The exporter derives `school_id` from the source network mapping and drops everything else in memory. Example: [`examples/events.csv`](../examples/events.csv).

## I6 · Public dataset (aggregator → public)

Produced by `vpr aggregate`. Format `vpr-dataset/2`, described by [`schemas/dataset.schema.json`](../schemas/dataset.schema.json).

- A release covers exactly one UTC day. CSV with header `<unit>,day,category,count`, where `<unit>` is `school_id` (school use case) or `unit_id` (any other use case); the encoding is the same, rows sorted by `(school_id, day, category, count)`, `\n` line endings, UTF-8. Cells `(school_id, day, category)` are unique.
- Rows with `count < k` are suppressed (default k = 10). The JSON summary reports `format`, `k`, `root` and `rows`. The number of suppressed cells is not published.
- Leaf: `keccak256(0x00 ‖ day:uint32 ‖ count:uint256 ‖ len(school_id):uint16 ‖ school_id ‖ len(category):uint16 ‖ category)`, big-endian, where `day` is the on-chain day number. Length prefixes make the encoding unambiguous, and the day binds a row to one anchored date.
- Internal node: `keccak256(0x01 ‖ min(a,b) ‖ max(a,b))`; leaves in row order; an odd node is promoted unchanged. Leaves and nodes are domain-separated as in RFC 9162. An empty release has no root and is not anchored.
- Anyone can check a release with `vpr verify-root dataset.csv <root>`, or a single row on-chain with `MetricsAnchor.verifyRow`.

## I7 · `MetricsAnchor` ABI

Source: [`contracts/src/MetricsAnchor.sol`](../contracts/src/MetricsAnchor.sol). Constructed with the address of the policy registry.

| Function | Caller | Effect | Reverts |
| --- | --- | --- | --- |
| `setPublisher(bytes32 scopeId, address publisher)` | the scope's current governor in the registry | Appoints or rotates the publisher (operator) | `UnknownScope`, `NotGovernor`, `ZeroAddress` |
| `commitRoot(bytes32 scopeId, uint32 day, bytes32 root, string datasetUri)` | publisher | Write-once root for a day | `NotPublisher`, `EmptyRoot`, `DayAlreadyCommitted` |
| `getCommitment(bytes32 scopeId, uint32 day) → (bytes32 root, string datasetUri, uint64 committedAt)` | view | Stored commitment | none |
| `leafHash(uint32 day, string schoolId, string category, uint256 count) → bytes32` | pure | Leaf of a row (I6) | `FieldTooLong` |
| `verifyRow(bytes32 scopeId, uint32 day, string schoolId, string category, uint256 count, bytes32[] proof) → bool` | view | Computes the leaf from the row and the anchored day, then checks the proof | `FieldTooLong` |
| `registry() → address`, `publisher(bytes32) → address` | view | Configuration | none |

Events: `PublisherSet(scopeId, governor, publisher)`, `RootCommitted(scopeId, day, root, datasetUri)`.

There is no first-caller configuration: the governor recorded in the registry is the only party that can appoint a publisher, and a governor rotation in the registry immediately transfers that power. The anchor accepts rows, not raw leaves, so an internal node cannot be presented as a row.

## I8 · EAS attestations

Definitions: [`schemas/eas-schemas.json`](../schemas/eas-schemas.json) (CC0). Registration on OP Sepolia and OP Mainnet is planned ([VPR-012](BACKLOG.md)); UIDs will be stored in `deployments/<network>.json`.

| Schema | Issuer | Fields |
| --- | --- | --- |
| `VPR.Deployment.v1` | operator | `string schoolId, bytes32 scopeId, uint256 policyVersion, bytes32 resolverConfigHash, uint64 deployedAt` |
| `VPR.IndependentTest.v1` | independent reviewer | `string schoolId, bytes32 scopeId, uint256 policyVersion, bool categoriesBlocked, bool exceptionsReachable, bool dnssecValidated, bool bypassResisted, bytes32 reportHash, uint64 testedAt, uint64 validUntil` |
| `VPR.Conformance.v1` | auditor | `bytes32 scopeId, string framework, string frameworkVersion, bytes32 reportHash, uint64 assessedAt, uint64 validUntil` |

All schemas are revocable. For `VPR.IndependentTest.v1`, the booleans are the public summary; `reportHash` commits to the full report, which is shared with the governor signers and not published, since a per-school account of bypass attempts can be useful to an attacker. Verifiers must check that the attester address belongs to the expected role for the scope, and that `validUntil` has not passed. A school counts as protected only with a valid, unrevoked `VPR.IndependentTest.v1` for the policy version in force.

## I9 · Appeal document (format 2; relayer planned, [VPR-017](BACKLOG.md))

An appeal is a small JSON document, canonicalised like a policy document (sorted keys, no whitespace, UTF-8). The contract stores only `documentHash = keccak256(canonical document)`:

```json
{
  "format": "vpr-appeal/2",
  "scope": "giga:XX:primary",
  "domain": "educational-site.example",
  "request": "unblock",
  "reason": "Used for the science curriculum in grade 5"
}
```

Rules enforced by the relayer before it files the hash: exactly these five keys; `request` is `unblock` or `block`; `domain` is a valid domain name; `reason` is at most 280 characters; no names, emails, school staff details or anything about a student. The relayer publishes accepted documents off-chain, keyed by their hash, and can withhold or take down a document that breaks these rules without affecting the on-chain record. Anyone can also file a hash directly; since only a hash reaches the chain, a direct filing cannot place free text on-chain, and an appeal whose document is never published is treated as unsubstantiated.

The governor answers each appeal with a reasoned decision. A rejection records the hash of the published reasoning; an acceptance records the content hash of the policy version that resolves it. A rejected document can be filed again, which opens a new round.

## I10 · Command-line interface

Installed with `pip install -e tools/`. Exit codes: `0` success, `1` verification mismatch, `2` invalid input or usage. `--json` prints one JSON object; errors go to stderr, never with a traceback, and never echo suppressed cells or restricted-list entries; any unexpected error exits with 2. `verify-row` without `--root` reports `anchored: false`; `verify-root --k K` checks the threshold, which the root does not commit to. The stable Python API is `vpr.toolkit` ([integration guide](toolkit/INTEGRATION_GUIDE.md)).

| Command | Input | Output |
| --- | --- | --- |
| `vpr policy-hash <policy>` | Policy document (I1) | `scope`, `scopeId`, `version`, `contentHash` |
| `vpr compile-rpz <policy> [--feeds-dir DIR] [--restricted FILE] [--block-page HOST] [--out FILE]` | Policy, feeds (`<category>.txt`, one domain per line, `#` comments), optional restricted list | RPZ zone (I4). Fails closed: a category without a feed, or a restricted list whose hash differs from the policy's, is an error |
| `vpr aggregate <events.csv> [--day YYYY-MM-DD] [--k N] [--out-csv FILE]` | Block events (I5); `--day` is required when they span several days | JSON summary on stdout, dataset CSV (I6) |
| `vpr evaluate <zone> <domain>… [--json]` | Compiled zone (I4) and domains | Action per domain (`passthru`, `redirect`, `nxdomain`, `allow`) and matching rule; a zone evaluation, not DNS resolution |
| `vpr prove-row <release.csv> --index N` | Release (I6) | JSON with the row, day number, leaf, proof and root |
| `vpr verify-row <proof.json> [--root R] [--json]` | Output of `prove-row`; optionally the anchored root | `MATCH` (exit 0) or `MISMATCH` (exit 1) |
| `vpr restricted-hash <list>` | Restricted list, one domain per line | Its commitment (I1); the list itself is never published |
| `vpr verify-root <dataset.csv> <root> [--k K] [--json]` | Dataset (I6) and expected root | `MATCH` (exit 0) or `MISMATCH` (exit 1) |

## Versioning of these interfaces

Interfaces follow the project's semantic version. Any change to hashing, leaf encoding, field sets or ABI signatures is a breaking change: it needs an ADR, a new format version (`vpr-appeal/2`, `VPR.Deployment.v2`, …) and an entry in [CHANGELOG.md](../CHANGELOG.md).
