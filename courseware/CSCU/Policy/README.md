# CSCU courseware — Copper State Credit Union (financial services)

The Policy Generator workshop set for the credit-union scenario. It follows
on from the Glossary repo's CSCU set (Workshops 00–05 + the Glossary
Generator app workshop + the Technical Track), picking up at the
**Classification Registry** hand-off.

## Workshops

| File | What it is |
| --- | --- |
| `Workshop-Policy-Generator-CSCU.md` | The UI-first Data Identification workshop — the app's full lifecycle (launch → Load → Author → Reconcile → Deploy → Drift-check, including the deliberate-drift exercise), with the CLI as an appendix — authoritative markdown master |
| `Workshop-Policy-Generator-CSCU.docx` | Generated from the master in the course design ([`tools/build-docx.py`](tools/)), with amber placeholder boxes where screenshots from the CSCU lab go |

The **reconcile**, **deploy** and **drift-check** stages shipped in app 1.8 —
and the workshop now covers them in the main arc: Deploy (dry-run plan, then
programmatic import over PDC's own worker API) and Drift-check
(clean / drifted / orphaned / missing verdicts) are workshop steps, not
modules still to be written. The `.docx` lags the markdown master until
regenerated with `tools/build-docx.py`.

## Prerequisites (owned by the Glossary repo)

Scenario data and the shared lab stack live in
[PDC-Glossary-Generator](https://github.com/jporeilly/PDC-Glossary-Generator):
`data_sources/CSCU/` (the `cscu_core` schema, the `cscu-documents` bucket,
the domain pack) and `data_sources/lab/` (demo-postgres on 5433 + demo-minio).
Complete that repo's CSCU **Glossary Generator app workshop** first — it
produces the Registry this workshop consumes.

*All Copper State Credit Union data is fictional and generated for training.*
