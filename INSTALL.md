# PDC-Demo — end-to-end install (Windows host + Ubuntu lab VM)

The one place that describes standing up the **whole demo estate**. Per-app
details stay in each app's own repo; this guide is the topology and the
order of operations.

## The topology

Two machines, fixed roles:

| Where | What runs there | Address |
| --- | --- | --- |
| **Windows 11 host** | The three apps in `C:\PDC-Demo` — Glossary Generator (:5000), Policy Generator (:5001), Catalog Insights (:8660) — plus Ollama (:11434) for the AI agents | your workstation |
| **Ubuntu 24.04 VM** | Pentaho Data Catalog 11 (Docker, `https://pentaho.io`) + the shared demo lab — PostgreSQL (:5433) and MinIO (:9000/:9001) — and optionally a `~/PDC-Demo` app checkout | static IP `192.168.1.200` |

Conventions that everything else assumes:

- **`pentaho.io` is PDC's HTTPS name** (self-signed cert). Map it on the
  Windows host in `C:\Windows\System32\drivers\etc\hosts`:
  `192.168.1.200  pentaho.io`
- **Data-source connections use the VM IP**, never `localhost` and never
  `pentaho.io`: PostgreSQL `192.168.1.200:5433`, MinIO
  `http://192.168.1.200:9000`.
- One vertical at a time: **CSCU**, **RETAIL**, **HEALTH** or **MFG**.

## 1. Windows host — the apps (one command)

Prerequisites: Git for Windows, Python 3.9+ (3.12+ recommended), Node 18+
(builds the Policy web UI), and optionally [Ollama](https://ollama.com) for
the AI agents.

```powershell
iex "& { $(irm https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.ps1) } CSCU"
```

This stands up (or updates — re-run it bare any time) **`C:\PDC-Demo`**:

```text
C:\PDC-Demo\
  glossary_generator\    the Glossary Generator app        -> .\run.ps1  :5000
  policy_generator\      the Policy Generator app (+ UI)   -> .\run.ps1  :5001
  PDC-Insights\          Catalog Insights                  -> .\run.bat  :8660
  PDC-Scenarios\         the selected vertical (sparse)
  courseware\            junction -> PDC-Scenarios\courseware
  docs\                  incl. PDC-VM-TROUBLESHOOTING.md
```

It also installs the vertical's domain pack + steward roster into the
Glossary app, builds the Policy React UI, and seeds Insights' `.env` with
`PDC_BASE_URL=https://pentaho.io` (edit `PDC-Insights\.env` to set
credentials, or set `INSIGHTS_DEMO=true` to explore without a live PDC).

Start each app and check it answers:

| App | Start | URL | First-run check |
| --- | --- | --- | --- |
| Glossary Generator | `cd C:\PDC-Demo\glossary_generator; .\run.ps1` | <http://127.0.0.1:5000> | version pill in the sidebar |
| Policy Generator | `cd C:\PDC-Demo\policy_generator; .\run.ps1` | <http://127.0.0.1:5001> | React UI loads (not just /docs) |
| Catalog Insights | `cd C:\PDC-Demo\PDC-Insights; .\run.bat` | <http://127.0.0.1:8660> | `/health` is green |

## 2. Ubuntu VM — PDC + the lab data sources

PDC itself is assumed installed at `/opt/pentaho/pdc-docker-deployment`
(rebuild/repair: `pdc-reset.sh` in the deployed checkout — see the
[troubleshooting doc](https://github.com/jporeilly/PDC-Glossary-Generator/blob/main/docs/PDC-VM-TROUBLESHOOTING.md)).
The lab sources sit beside it:

```bash
# one bootstrap: apps + this repo (sparse) into ~/PDC-Demo
curl -fsSL https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.sh | bash -s -- CSCU

# lab up + the vertical's database + bucket loaded
cd ~/PDC-Demo/PDC-Scenarios && make scenario ID=CSCU

# the vertical's cast -> Keycloak users + PDC roles
./load-pdc-users.sh CSCU
```

`make status` shows the lab; `make console` prints the per-scenario
connection values PDC needs. Details: [data_sources/lab/README.md](data_sources/lab/README.md).

## 3. Connect PDC to the lab sources

In PDC (`https://pentaho.io`) add the two data sources — or bulk-load them
in the Glossary app (Connect → bulk loader) from the vertical's
`*-datasources.csv`:

- **PostgreSQL** — host `192.168.1.200`, port `5433`, database/schema and
  read-only user per the table in
  [data_sources/lab/README.md](data_sources/lab/README.md)
- **MinIO/S3** — endpoint `http://192.168.1.200:9000`, the vertical's
  bucket + its read-only MinIO user

Then follow the vertical's courseware (`courseware/<ID>/`) — Workshops 0–5,
plus the Glossary and Policy app workshops.

## Updating

Re-run the same bootstrap (bare — the vertical is remembered):

- Windows: `iex "& { $(irm https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.ps1) }"`
- VM: `curl -fsSL https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.sh | bash`

After an update: restart the apps; in the Glossary app click the version
pill (it flags a pulled-but-not-restarted build).

## Ports at a glance

| Port | What | Where |
| --- | --- | --- |
| 5000 | Glossary Generator | Windows host |
| 5001 | Policy Generator | Windows host |
| 8660 | Catalog Insights (8765 for its optional MCP server) | Windows host |
| 11434 | Ollama | Windows host |
| 443 | PDC (`https://pentaho.io`) | VM |
| 5433 | lab PostgreSQL (5432 belongs to PDC's own database) | VM |
| 9000/9001 | lab MinIO (S3 API / console) | VM |

## Troubleshooting

- **PDC platform down / site-wide 404 / OpenSearch init loop** —
  [PDC-VM-TROUBLESHOOTING.md](https://github.com/jporeilly/PDC-Glossary-Generator/blob/main/docs/PDC-VM-TROUBLESHOOTING.md)
  and `pdc-reset.sh` (both at the top level of a deployed `~/PDC-Demo`).
- **Cert warning at `https://pentaho.io` with no "Proceed"** — type
  `thisisunsafe` blind on the Chrome error page, or import the cert.
- **Lab stack** — [data_sources/lab/README.md](data_sources/lab/README.md)
  (idempotent loads, `make remove` to rebuild a scenario).
