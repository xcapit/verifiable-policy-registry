# Second reference use case: public-service interruptions

*CC BY 4.0 · Synthetic data only.*

This example shows that the verification toolkit is not tied to schools or to content filtering. A utility, or a regulator overseeing it, publishes how many water-service interruptions were reported per district, per day and per cause. It wants three properties: residents can check that the published figures were not altered later; districts with very few reports are not singled out; and nobody's household data is published.

[`events.csv`](events.csv) contains synthetic reports for one day, one row per report, with only `unit_id` (a district), `day` and `category` (the cause). The same tools and the same on-chain verifier used for school filtering apply unchanged:

```bash
vpr aggregate examples/public-service/events.csv --k 10 --unit-column unit_id --out-csv /tmp/water.csv
vpr verify-root /tmp/water.csv <root printed above>
vpr prove-row /tmp/water.csv --index 0 > /tmp/proof.json
vpr verify-row /tmp/proof.json
```

With *k* = 10, the cells for district-n02 pipe bursts (4 reports), district-n03 contamination alerts (2) and district-n04 pressure loss (7) are suppressed. Neither their values nor their existence appear in the published release. The end-to-end demo ([`examples/e2e/run.sh`](../e2e/run.sh)) anchors this release under its own scope and verifies one of its rows with `MetricsAnchor.verifyRow`, next to the school release.

What this example does **not** show: that the reports are complete or truthful. As in the school case, the commitment covers what the publisher aggregated, not what happened in the field (see [the cryptographic evidence pack](../../docs/security/ZK_AND_CRYPTOGRAPHIC_EVIDENCE.md)).
