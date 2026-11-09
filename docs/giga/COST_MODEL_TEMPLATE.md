# Cost model template

*CC BY 4.0 · Proposal package for a school pilot · v0.4.0*

A template for computing the cost of running the system per school. **No figure here is an estimate.** Every input is either a formula over measured quantities or marked "Unknown — input required (owner, milestone)". The cost drivers are the same as in [../SUSTAINABILITY.md](../SUSTAINABILITY.md); this page turns them into a worksheet.

## Inputs

| Symbol | Input | Unit | Value |
| --- | --- | --- | --- |
| S | Schools served by one resolver pair | schools | Unknown — input required (Giga/ministry, M1) |
| S_scope | Schools in one policy scope | schools | Unknown — input required (Giga/ministry, M1) |
| H | Monthly cost of one resolver pair in the chosen region | currency/month | Unknown — input required (operator, M1 week 1, quotes) |
| B | Monthly bandwidth and monitoring cost for the resolver site | currency/month | Unknown — input required (operator, M2) |
| R_hour | Reviewer hourly rate | currency/hour | Unknown — input required (reviewer, M1 week 2) |
| R_h | Reviewer hours per school per test cycle | hours | Unknown — input required (reviewer, M2) |
| C | Test cycle length | months | Unknown — input required (reviewer and governing institutions, M1) |
| D_month | Days in the billing month | days/month | Calendar input for the period being costed |
| A | Public attestations per school per test cycle | attestations | Unknown — input required (reviewer, M1) |
| g_att | Gas per attestation | gas | Unknown — measured on the test network (operator, M2) |
| g_root | Gas per daily root anchoring | gas | Unknown — measured on the test network (operator, M2) |
| g_pol | Gas per policy version | gas | Unknown — measured on the test network (operator, M2) |
| p_gas | Gas price × currency per unit of gas on the chosen network | currency/gas | Unknown — at the time of operation |
| V | Policy versions per month per scope | versions/month | Unknown — derived from the Gate A validity bound and actual change rate |
| P_h | Prover machine cost per hour (from M4) | currency/hour | Unknown — benchmarks (VPR-036, M4) |
| P_t | Proving hours per scope per day (from M4) | hours/day | Unknown — benchmarks (VPR-036, M4) |
| g_ver | Gas per proof verification (from M4) | gas | Unknown — benchmarks (VPR-036, M4) |
| L | Threat-feed and restricted-list licences | currency/month | Unknown — input required (operator and ministry, M1) |
| g_app | Gas per appeal filed or answered through the relayer, and appeals per month | gas, appeals/month | Unknown — measured on the test network (operator, M2) |
| F | Fixed monthly costs per country (dashboard, mirroring, support, policy staff time) | currency/month | Unknown — input required (operator and ministry, before Gate C) |

## Formulas, per school per month

| Line | Formula |
| --- | --- |
| Resolver hosting | H ÷ S |
| Bandwidth and monitoring | B ÷ S |
| Independent testing | R_hour × R_h ÷ C |
| Attestations on the public record | A × g_att × p_gas ÷ C |
| Daily summaries on the public record | D_month × g_root × p_gas ÷ S_scope |
| Policy versions on the public record | V × g_pol × p_gas ÷ S_scope |
| Proof generation (from M4) | P_h × P_t × D_month ÷ S_scope |
| Proof verification (from M4) | D_month × g_ver × p_gas ÷ S_scope |
| Share of fixed country costs | F ÷ (schools served by the deployment) |
| Feed and list licences | L ÷ S |
| Appeal relayer gas | g_app × appeals per month × p_gas ÷ S_scope |

**Total per school per month** = the sum of the lines above.

## Notes for reviewers

- The public-record lines depend on scope size, not on traffic: one daily transaction per scope regardless of how many schools or queries. Their share per school falls as a scope grows.
- Filtering itself has no per-query fee to any third party; the resolver is open-source software on ordinary infrastructure.
- The cost model assumes that participating schools would not be charged directly during a funded pilot. This is a proposal assumption, not an agreed commitment; the funding source and post-pilot payer are open decisions ([OPERATING_MODEL.md](OPERATING_MODEL.md)).
- Costs that the pilot does not cover and that may exist in the country: provider configuration fees, procurement overhead, translation of materials, training sessions. Each is Unknown — input required (ministry/provider, M1).

## How figures will be filled in

1. M1: hosting quotes and reviewer rates are obtained and entered with their source.
2. M2: gas per operation is measured on the test network during the alpha and entered with the transaction references.
3. M4: proving costs come from the published benchmarks.
4. Gate C: a completed worksheet, with every value sourced, is part of the evaluation evidence.
