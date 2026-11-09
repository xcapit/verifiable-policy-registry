# Policy governance

*CC BY 4.0*

This page covers who governs each **filtering policy**. How the open-source project itself is run is described in [GOVERNANCE.md](../GOVERNANCE.md) at the repository root.

## Roles

| Role | Who (pilot) | Powers | Cannot |
| --- | --- | --- | --- |
| Governor | Safe multisig 2-of-3: UNICEF Giga, Ministry of Education, independent reviewer | Publish policy versions, accept or reject appeals, rotate governor | Act with a single signature |
| Operator | Xcapit | Run resolver, publish datasets and roots, attest deployments | Change policy, attest its own tests |
| Independent reviewer | Child-protection NGO or university | Third signer; test schools; attest tests; review appeals | Operate the resolver |
| Auditor | Third party | Attest conformance to standards | Govern |
| Public | Anyone | Read everything, file appeals, recompute roots | — |

## Reason codes

Used in `publishPolicy(..., reasonCode, ...)` and in policy documents.

| Code | Meaning |
| --- | --- |
| 1 | `initial_policy`: first version for a scope |
| 2 | `scheduled_renewal`: re-signing before expiry, no content change |
| 3 | `appeal_accepted`: resolves an appeal (set `resolvesAppeal`) |
| 4 | `new_threat`: new malware/phishing category or feed |
| 5 | `legal_requirement`: change required by law (must cite it in the document) |
| 6 | `correction`: fixes an error in a previous version |

## Rules

1. Every local block and exception in a policy document states its reason.
2. Maximum validity per scope: 90 days in the pilot. Renewal is a signed act.
3. Appeals are answered within 5 working days (pilot target).
4. Restricted lists are referenced only by hash; their use is stated in the document.
5. The charter of each scope defines the fallback when a policy expires without renewal (recommended: protective-only categories: malware and phishing).
6. Key management: hardware wallets or passkey-based smart accounts for institutional signers; documented recovery; signer rotation via Safe and `setGovernor`.
