# PDC-Scenarios — the training verticals, one repo

Every per-scenario asset for the PDC training pipeline lives here, one
folder per vertical: the **data kit** (lab SQL, documents, bulk-load CSV),
the **domain pack** (governed vocabulary + steward roster), and the
**courseware** for the platform and both apps. The apps themselves stay in
their own repos — this repo is what gets deployed when you pick a vertical.

| Vertical | Industry | Data kit | Courseware |
| --- | --- | --- | --- |
| **CSCU** — Copper State Credit Union | Financial services | [data_sources/CSCU/](data_sources/CSCU/) | [courseware/CSCU/](courseware/CSCU/) |
| **RETAIL** — Canyon Trail Outfitters | Retail | [data_sources/RETAIL/](data_sources/RETAIL/) | [courseware/RETAIL/](courseware/RETAIL/) |
| **HEALTH** — Lakeshore Health Partners | Healthcare | [data_sources/HEALTH/](data_sources/HEALTH/) | [courseware/HEALTH/](courseware/HEALTH/) |
| **MFG** — Cascade Precision Components | Manufacturing | [data_sources/MFG/](data_sources/MFG/) | [courseware/MFG/](courseware/MFG/) |

The two apps this repo feeds:

- **[Glossary Generator](https://github.com/jporeilly/PDC-Glossary-Generator)** —
  scans the scenario's sources, builds the governed glossary, writes the
  Classification Registry. `install-scenario.sh <ID>` installs the vertical's
  domain pack + roster into it.
- **[Policy Generator](https://github.com/jporeilly/PDC-Policy-Generator)** —
  reads the Registry and authors PDC's Data Identification methods.

## Select a vertical

```bash
git clone --filter=blob:none https://github.com/jporeilly/PDC-Scenarios.git
cd PDC-Scenarios
./select-vertical.sh CSCU        # sparse-pulls ONLY this vertical (+ shared lab)
```

`select-vertical.sh` narrows the checkout to `data_sources/lab`,
`data_sources/<ID>` and `courseware/<ID>` — run it again to switch verticals,
`--all` for everything. Then:

```bash
cd data_sources/lab && make up && make load SCENARIO=CSCU   # stand up the sources
cd ../.. && ./install-scenario.sh CSCU                      # pack + roster into the Glossary app
```

`install-scenario.sh` finds the Glossary app automatically (this repo cloned
beside/inside the app checkouts, e.g. the lab VM's `~/PDC-Demo`) or via
`GLOSSARY_APP_DIR=/path/to/glossary_generator`. `reset-scenario.sh` removes
the installed scenario again. One scenario at a time — rerunning the
installer switches and backs everything up.

## Layout

```text
data_sources/
  lab/                ONE PostgreSQL + ONE MinIO for all verticals;
                      make load SCENARIO=<ID> creates that vertical's db + bucket
  <ID>/               the vertical's kit: scenario.json manifest, postgres-init
                      SQL, documents, domain pack + install zip, bulk-load CSV
courseware/
  <ID>/               the vertical's workshop sets: PDC platform Workshops 00-05,
                      the Glossary Generator app workshop (+ Technical Track on
                      CSCU), and Policy-Generator/ (the Policy app workshop);
                      each set's tools/build-docx.py regenerates its .docx
  PDC-Users-All-Scenarios.{csv,md}   consolidated user roster, all verticals
diagrams/             app diagrams the courseware builders embed
install-scenario.sh   install a vertical's pack + roster into the Glossary app
reset-scenario.sh     remove it again (reset the app to generic)
select-vertical.sh    sparse-pull just one vertical from this repo
```

New verticals plug in the same way: a `data_sources/<ID>/` with a
`scenario.json` beside a `courseware/<ID>/` set — no code changes anywhere.

*All scenario data — Copper State Credit Union, Canyon Trail Outfitters,
Lakeshore Health Partners and Cascade Precision Components — is fictional and
generated for training.*
