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
| Celo (Prezenti) | Grant pools for builders on Celo, community-funded ([listing](https://grantedai.com/grants/celo-foundation-grants-prezenti-grants-celo-public-goods-grants-celo-foundation-087887f3)) | Social-impact and Latin American focus. Requires deployment on Celo | Last round ran 25 Feb–30 Jun 2026; next round not announced |
| TheDAO Security Fund (ETHSecurity Initiatives) | Ethereum security initiatives. A proposed initiative that is fully pledged opens a 30-day RFP, a team is selected and paid by milestone; otherwise ETHSecurity badge holders vote at year end ([submit](https://initiatives.thedao.fund/submit/)) | Only for work that improves Ethereum security. The school pilot does not fit. A derived initiative could: public, threshold-governed, expiring and contestable blocklists of wallet-drainer and phishing domains, reusing the registry and EAS schemas. Proposing an initiative does not reserve it for the proposer: the RFP is open | Round Two accepting proposals until late January 2027 ([report](https://cryptobriefing.com/ethsecurity-round-two-onchain-security/)) |
| Gitcoin and Octant rounds | Community and quadratic-funding rounds for public goods ([Gitcoin directory](https://explore.gitcoin.co/apps)) | Small amounts; useful for visibility and evidence of community support | Per round |
| ZKsync | No open grant programme for applications found; 2026 governance allocations go to protocol, security and community programmes | Low as a grant. Its institutional focus is private chains, which conflicts with public verifiability | Not applicable |

## 3. Pilot operations

Hosting, the independent reviewer and support during the alpha are a service to one deployment. They are expected to come from the deploying partners or from programme funds (for example UNICEF and Giga programme budgets), not from a tooling grant. No such funding exists yet ([operating model](../giga/OPERATING_MODEL.md)).

## 4. Rules for any application

- Request funding only for open outputs listed in [PROPOSED_SCOPE_AND_MILESTONES](PROPOSED_SCOPE_AND_MILESTONES.md), adapted to the programme's call.
- Do not request the same deliverable from two programmes; if two programmes fund parts of one milestone, state the split in both applications.
- Check every status in this table again on the day of submission.
