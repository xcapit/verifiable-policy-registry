# Operating model

*CC BY 4.0 · Proposal package for a school pilot · v0.3 preparation*

Proposed allocation of work during a pilot, together with the decisions required for maintenance, funding and handover. Every holder below is provisional; no institution has accepted a role (see [OPEN_QUESTIONS_FOR_GIGA.md](OPEN_QUESTIONS_FOR_GIGA.md)).

## Roles

| Role | Proposed holder | Main responsibilities |
| --- | --- | --- |
| Ministry of Education | Pilot country ministry (to be confirmed) | Approves schools and content policy; one of the governing signers; owns the national decision to continue |
| Giga counterpart | Giga country or programme team (to be confirmed) | Selects schools from Giga Maps; one of the governing signers; links the pilot to Giga's connectivity programme |
| Independent reviewer | Child-protection NGO or university (to be confirmed) | Third governing signer; tests schools; reviews appeals and over-blocking reports |
| Operator | Xcapit, proposed for the pilot | Would run resolvers, exporter, daily job and block page; publishes datasets |
| Implementer | Xcapit, proposed (team in [../../MAINTAINERS.md](../../MAINTAINERS.md)) | Would build and maintain the software and train operators |
| Auditor | External firm (to be selected, M1) | Audits contracts and resolver configuration |
| Connectivity provider | Provider contracted for the schools (to be confirmed) | Redirects school DNS, blocks external resolvers, supports rollback |
| School | Head teacher or ICT focal point | Reports wrongly blocked sites; informs the community; no technical operation |

## Proposed RACI

R = responsible, A = accountable, C = consulted, I = informed.

| Activity | Ministry | Giga | Reviewer | Operator | Implementer | Auditor | Provider | School |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Select pilot schools | A | R | C | I | I | — | C | I |
| Approve a policy version | A/R (signer) | R (signer) | R (signer) | C | C | — | I | I |
| Compile and load the policy | I | I | I | R/A | C | — | — | — |
| Redirect DNS and block bypass | I | C | I | C | C | — | R/A | I |
| Test each school | I | I | R/A | C | C | — | C | I |
| Daily publication of summaries | I | I | C | R/A | C | — | — | — |
| Handle an appeal | C | R (signer) | R (review) | R (intake) | C | — | — | C |
| Respond to an incident | A (policy incidents) | C | C | R (technical) | R | — | R (network) | I |
| Audit | I | I | C | C | C | R/A | — | — |
| Decide on phase 2 | A | R | C | C | C | — | C | I |

The operator never tests its own deployment and never approves a policy alone; see [../adr/0005-issuer-separation.md](../adr/0005-issuer-separation.md).

## Maintenance and upgrades

- **Policy renewal:** every policy version expires. The proposed pilot maximum is 90 days, subject to Gate A approval; the charter sets the renewal lead time and the signers approve each version.
- **Threat feeds:** updated by reference to provider and version in the policy document; a feed update that changes categories requires a new signed version.
- **Software updates:** resolver and tools updates are tested on the test network first, announced to the signers, and applied outside school hours. Contract changes are not upgrades in place: a new contract is deployed and the old record stays readable.
- **Support:** a support line (email and phone, Unknown — input required, operator, M1) for schools and the ministry during school hours of the pilot country.

## Key management

- Each governing signer holds its own key in a hardware wallet or a passkey-based account; nobody holds another institution's key.
- A key ceremony at Gate A records who holds which key, how it is backed up and how it is replaced.
- Two of three signatures are required for any policy change. A lost or compromised key is replaced through the same two-of-three rule.
- The operator's publishing key can only publish daily summaries; it cannot change policies. The governing institutions can replace it at any time.

## After the pilot: who operates, who pays

Operating options are described in [../SUSTAINABILITY.md](../SUSTAINABILITY.md): the ministry, the connectivity provider as part of the service, a regional host (Giga or partner), or Xcapit under contract as a transition. The pilot does not presuppose any of them.

| Decision | Owner | When |
| --- | --- | --- |
| Who operates after week 16 | Unknown — decision by confirmed partners | Before Gate C |
| Who pays operating costs | Unknown — input required from confirmed partners | Before Gate C |
| Whether to continue to phase 2 | Confirmed governing institutions, on the evaluation evidence | At Gate C |

If no operator or funding is agreed, the behaviour in [../SUSTAINABILITY.md](../SUSTAINABILITY.md) applies: filtering continues on the last policy, expiry still applies, records freeze but remain verifiable, and attestations lapse so that no school is shown as protected without a current test.

## Dependencies on government and providers

- Written agreement from the provider to redirect DNS and block external resolvers for pilot schools.
- Ministry approval of the content policy and of the DPIA.
- National data-protection requirements on hosting location (data residency), to be confirmed in the DPIA.
- Any procurement step required to engage the operator or the reviewer.
