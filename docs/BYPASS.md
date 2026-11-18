# Bypass: other resolvers, encrypted DNS and VPNs

*CC BY 4.0 · Answers in one place the question "what if a student uses another DNS or a VPN?" The details are in the documents linked from each answer.*

## The short answer

DNS-level filtering stops most attempts to use another resolver, provided the connectivity provider enforces it. It cannot stop a VPN, a tunnel or a connection outside the school network. VPR does not make the filter stronger. It makes the claim about the filter **verifiable and honest**:
- the independent reviewer tests bypasses from inside each school;
- the result is recorded in the attestation (`bypassResisted` in `VPR.IndependentTest.v1`, [INTERFACES I8](INTERFACES.md#i8--eas-attestations));
- a school whose provider cannot enforce DNS is reported as **not protected**, not as attested ([ROADMAP, schedule risks](ROADMAP.md#schedule-risks)).

A school or ministry that needs more than DNS filtering has to add other controls, listed below. They are outside VPR.

## Case by case

| What the user does | Stopped at the DNS layer? | How | Checked by | Residual |
| --- | --- | --- | --- | --- |
| Configures another resolver (for example `8.8.8.8`) on port 53 | Yes, if the provider enforces it | The provider redirects or blocks outbound port 53 to resolvers other than the pilot resolvers ([ARCHITECTURE, deployment conditions](ARCHITECTURE.md#deployment-conditions)) | Reviewer test kit (VPR-018) | None while the rule is in place; a missing rule fails the test |
| DNS over TLS (port 853) | Yes, if the provider enforces it | Outbound port 853 is blocked | Reviewer test kit | As above |
| DNS over HTTPS to a known public endpoint, set in the browser or the operating system | Mostly | The provider blocks known DoH endpoints. Firefox does not enable DoH by default when the network's resolver answers NXDOMAIN for the canary domain `use-application-dns.net`; the pilot resolver should do so | Reviewer test kit | Endpoints not on the list; a user who forces DoH on |
| DNS over HTTPS to an unknown or self-hosted endpoint | No | It looks like ordinary HTTPS traffic | Partly: the kit tests known endpoints only | Accepted and reported |
| VPN, Tor or a proxy | No | A tunnel carries its own DNS | The kit can test known VPN services | Accepted and reported. Blocking known VPN endpoints at the provider is possible but incomplete |
| Mobile data or a personal hotspot | No | The device is no longer on the school network | Not applicable | Outside the network, outside the scope |
| Hard-coded IP addresses | No | No DNS lookup is made | Not applicable | DNS filtering acts on names only |
| A page on an otherwise legitimate domain | No | DNS sees the domain, not the URL | Not applicable | Needs a URL-level control ([white paper §10](WHITEPAPER.md#10-limitations)) |

## Complementary controls a school may need

These controls are conventional, and VPR neither provides nor attests them.

- **An egress firewall at the provider or the school:** blocks DNS on ports 53 and 853 except to the pilot resolvers, blocks known DoH and VPN endpoints, and restricts protocols the school does not need.
- **Device management** on school-owned devices: managed browser settings, DoH disabled or pinned to the network resolver, and no installing VPN apps.
- **Filtering at the browser or proxy level**, where URL-level blocking is required.
- **Supervision and digital-literacy education.** The white paper is explicit that filtering complements them and does not replace them ([§3.5](WHITEPAPER.md#35-non-goals)).

The scope charter should state which of these the deployment relies on, so that the reviewer tests what is claimed and nothing more.

## Where this is written down

- White paper, adversary A7 (a user bypassing the filter): [§6.2](WHITEPAPER.md#62-adversaries).
- Provider configuration and fail-closed behaviour: [ARCHITECTURE, deployment conditions](ARCHITECTURE.md#deployment-conditions).
- Pilot boundaries: [PILOT_ARCHITECTURE, explicit boundaries](giga/PILOT_ARCHITECTURE.md#explicit-boundaries).
- Reviewer test kit: [BACKLOG VPR-018](BACKLOG.md).
- Evaluation metric "attested schools passing the periodic bypass test": [white paper §9](WHITEPAPER.md#9-evaluation-plan).
