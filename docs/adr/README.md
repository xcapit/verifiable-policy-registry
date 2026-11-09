# Architecture decision records

*CC BY 4.0*

Each record captures one decision, the context in which it was taken and what it costs. Records are numbered and never deleted: a decision that changes is marked *Superseded* and a new record explains why.

Template: [0000-template.md](0000-template.md).

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-licensing.md) | AGPL-3.0 for code, CC0 for schemas, CC BY 4.0 for docs | Accepted |
| [0003](0003-commit-dont-store-on-op-mainnet.md) | Commit, do not store: hashes on OP Mainnet with EAS | Accepted |
| [0004](0004-multisig-governor-expiry-appeals.md) | Multisig governor per scope, mandatory expiry, on-chain appeals | Accepted |
| [0005](0005-issuer-separation.md) | Separate issuers: the operator never certifies itself | Accepted |
| [0006](0006-scope-school-networks-only.md) | Scope limited to bounded networks such as schools | Accepted |
| [0007](0007-k-anonymous-metrics-merkle.md) | Threshold-suppressed metrics (k = 10) with a daily Merkle root | Accepted |
| [0008](0008-restricted-lists-hash-only.md) | Restricted lists by hash commitment only | Accepted |
| [0009](0009-generic-verification-toolkit.md) | A use-case-independent verification toolkit | Accepted |
| [0010](0010-category-and-unit-sets-on-chain.md) | Category and unit sets committed on-chain for the ZK relation | Proposed |
