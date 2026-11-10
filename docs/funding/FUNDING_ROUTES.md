# Funding routes

*CC BY 4.0 · Part of the funding evidence package ([index](EVIDENCE_INDEX.md)). Programmes change their calls often: every status below carries the date it was checked and its source, and must be checked again before any application. Listing a programme implies no contact with it, no eligibility and no endorsement.*

## 1. How the work splits

The proposed phase 1 ([roadmap](../ROADMAP.md)) has three kinds of cost, and no single programme funds all three:

| Part | Milestones | Nature | Typical funder |
| --- | --- | --- | --- |
| Reusable tooling | M1 specifications, M4 zero-knowledge verifier, toolkit and schemas | Open infrastructure for other builders | Public-goods and ecosystem programmes |
| Audit | M3 audit of the registry, anchor and resolver configuration | Security of deployed contracts | Audit subsidy programmes |
| Pilot operations | M2 alpha: resolver hosting, independent reviewer, support | Service to a specific deployment | Programme or partner funds, not tooling grants |

## 2. Programmes considered

| Programme | What it funds | Fit | Status (checked 2026-11-10) |
| --- | --- | --- | --- |
| Ethereum Foundation ESP | Open-source, non-commercial work aligned with CROPS, through Wishlist items and RFPs; support is directed to builders rather than end users ([applicants page](https://esp.ethereum.foundation/applicants), [announcement](https://blog.ethereum.org/2025/11/03/new-esp-grants)) | Reusable tooling, especially the zero-knowledge verifier and the attestation schemas | No open Wishlist item or RFP listed. Office Hours available for feedback |
| Optimism Collective | Retro Funding for impact already delivered on the Superchain, and Mission Grants for work completed over 12 months ([get a grant](https://community.optimism.io/docs/governance/get-a-grant/)) | Reference deployment is OP Mainnet; registry and anchor as Superchain infrastructure. Retro Funding applies only after there is measurable use | Check the current season before applying |
| Arbitrum Audit Program | Subsidies for third-party smart-contract audits, $10M in ARB over 12 months ([Arbitrum grants](https://arbitrum.foundation/grants)) | M3 audit cost. Requires a deployment on Arbitrum, which would also exercise a second network (DPG indicator 4) | Active |
| Base Builder Grants | Small retroactive grants for shipped work on Base ([ethereum.org founders](https://ethereum.org/en/founders/)) | Low: small amounts, Base is the fallback network | Ongoing |
| Celo (Prezenti, Season 3) | Milestone grants of $3K–$50K for Celo apps with traction (from 5,000 daily transactions) and for AI-agent infrastructure; requires a Celo mainnet deployment ([listing](https://www.web3grant.com/grants/celo-public-goods-round)) | Low: the programme replaced Celo's public-goods rounds and selects on on-chain traction, which VPR does not have | Listed as open until 29 Dec 2026, with conflicting notices on the official site |
| TheDAO Security Fund (ETHSecurity Initiatives) | Initiatives that make Ethereum or its L2s measurably safer: wallet and signing security, incident detection and response, testing and audit tooling, client and L2 security. Not funded: research without a clear user, general developer tooling, or a project's own audit. Each initiative needs adoption milestones worth at least a third of its budget. Past grants ranged from $10K to $640K. A fully pledged initiative opens a 30-day RFP open to any team ([submit](https://initiatives.thedao.fund/submit/), [listing](https://www.web3grant.com/grants/thedao-security-fund)) | The school pilot does not fit, and the registry audit is excluded. A derived wallet-security initiative could fit: public, threshold-governed, expiring and contestable blocklists of wallet-drainer and phishing domains, reusing the registry and EAS schemas, with wallet integrations as adoption milestones | Round Two open until 31 Jan 2027; badge-holder allocation in mid-November ([report](https://cryptobriefing.com/ethsecurity-round-two-onchain-security/)) |
| Stellar Development Foundation, Academic Research Grants | Unrestricted gifts of up to $150K (historical average about $75K) to a degree-granting institution for one graduate student or postdoc for 12 months; focus areas include privacy-preserving payments and zero-knowledge proofs, and formal verification; research need not be about Stellar; three-page proposal, no patents ([listing](https://www.web3grant.com/grants/stellar-academic-research-grants)) | The zero-knowledge aggregation research (M4) as novel research led by a principal investigator at UTN Facultad Regional Villa María. Funds research, not the deployment | Quarterly windows; current one closes 31 Dec 2026 |
| Ava Labs Security Audit Program | Audit subsidies for projects on Avalanche ([listing](https://www.web3grant.com/grants/ava-labs-audit-subsidy)) | Alternative to the Arbitrum programme for the M3 audit; requires an Avalanche C-Chain deployment (EVM) | Rolling |
| Gitcoin and Octant rounds | Community and quadratic-funding rounds for public goods ([Gitcoin directory](https://explore.gitcoin.co/apps)) | Small amounts; useful for visibility and evidence of community support | Per round |
| ZKsync | No open grant programme for applications found; 2026 governance allocations go to protocol, security and community programmes | Low as a grant. Its institutional focus is private chains, which conflicts with public verifiability | Not applicable |

## 3. Pilot operations

Hosting, the independent reviewer and support during the alpha are a service to one deployment. They are expected to come from the deploying partners or from programme funds (for example UNICEF and Giga programme budgets), not from a tooling grant. No such funding exists yet ([operating model](../giga/OPERATING_MODEL.md)).

## 4. Rules for any application

- Request funding only for open outputs listed in [PROPOSED_SCOPE_AND_MILESTONES](PROPOSED_SCOPE_AND_MILESTONES.md), adapted to the programme's call.
- Do not request the same deliverable from two programmes; if two programmes fund parts of one milestone, state the split in both applications.
- Check every status in this table again on the day of submission.
