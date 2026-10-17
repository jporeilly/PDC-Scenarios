# Google Sheets → lab PostgreSQL with Pentaho

How to pull a **private** Google Sheet into the demo lab's PostgreSQL
(`192.168.1.200:5433`) with Pentaho Data Integration (PDI). Only PDI is
needed — the same job works against any PostgreSQL by changing the
connection.

```text
Google Sheet ──(service account, HTTPS)──► PDI job ──► PostgreSQL
 (private)        CSV export per tab       kjb + ktr    <db>.<schema>.<table>
```

## 1. One-time Google setup (service account)

1. In the [Google Cloud console](https://console.cloud.google.com/) pick or
   create a project, then **APIs & Services → Enable APIs** and enable the
   **Google Drive API** (and the **Google Sheets API** if you also want the
   JSON values endpoint).
2. **IAM & Admin → Service accounts → Create service account** (no project
   roles needed). Open it → **Keys → Add key → JSON** and download the key.
3. Copy the key to the machine that runs PDI, e.g.
   `~/PDC-Demo/secrets/gsheets-sa.json` (Windows host:
   `C:\PDC-Demo\secrets\gsheets-sa.json`). Keep it out of git.
4. Open the Google Sheet → **Share** → add the service account's
   `client_email` (from the JSON, `…@….iam.gserviceaccount.com`) as
   **Viewer**. Without this step every request returns 403/404.
5. Note two IDs from the sheet URL
   `https://docs.google.com/spreadsheets/d/<SPREADSHEET_ID>/edit#gid=<GID>`:
   the **spreadsheet ID** and the **gid** of each tab you want.

## 2. Token helper (PDI has no Sheets service-account step)

PDI ships no maintained Google Sheets input step (the old *Google Spreadsheet
Input* Marketplace plugin is unmaintained and does not work with current
Google auth). Instead, a short helper mints an OAuth access token from the
service-account key, and PDI's standard HTTP entry does the download.

Install the library once on the PDI machine: `pip install google-auth requests`.

Save as `~/PDC-Demo/secrets/gsheets-token.py`:

```python
import sys
from google.oauth2 import service_account
from google.auth.transport.requests import Request

key_file, out_file = sys.argv[1], sys.argv[2]
creds = service_account.Credentials.from_service_account_file(
    key_file, scopes=["https://www.googleapis.com/auth/drive.readonly"])
creds.refresh(Request())
with open(out_file, "w") as f:
    f.write("token\n" + creds.token + "\n")
```

The token lasts about an hour, so the job mints a fresh one on every run.

## 3. PDI database connection (lab Postgres)

In Spoon: **View → Database connections → New**.

| Field | Value |
| --- | --- |
| Connection name | `lab_postgres` |
| Type | PostgreSQL (Native JDBC) |
| Host | `192.168.1.200` (or `localhost` when PDI runs on the VM) |
| Port | `5433` |
| Database | the target db, e.g. a dedicated `pentaho_exams` (create it once: `CREATE DATABASE pentaho_exams;`) |
| User / password | `demo_admin` / value of `PG_ADMIN_PASSWORD` in `data_sources/lab/.env` |

Write as **`demo_admin`** (or another account that can create tables) —
the lab's `pdc_user` is read-only. Keep the results in their own database
rather than a scenario db: `make remove SCENARIO=<ID>` drops a scenario's
whole database.

## 4. The PDI jobs — one tab per exam

The sheet has **one tab per exam**. The jobs below load every tab into a
**single `exam_results` table** with an `exam` column, so one query can
compare exams (`GROUP BY exam`). This assumes all the tabs have the
same columns (true when each tab is a copy of the same Google Form's
responses). If the columns differ between tabs, see
[Tabs with different columns](#tabs-with-different-columns).

```text
gsheets_to_postgres.kjb (parent)
  token ─► set_token.ktr ─► empty exam_results ─► list_tabs.ktr
                                                     │ one row per exam tab
                                                     ▼
                              load_tab.kjb  (runs once per row: EXAM, SHEET_GID)
                                HTTP export of that tab ─► load_sheet.ktr ─► append
```

### Find each tab's gid

Click each exam tab in the browser. The URL ends in `#gid=<number>`, and
that number is the tab's `gid` (the first tab is usually `0`). Write down
an exam name and gid for every tab, e.g.:

| exam | gid |
| --- | --- |
| `PDI-Fundamentals` | `0` |
| `PDC-Admin` | `184734512` |
| `Pentaho-Server` | `920113877` |

A gid doesn't change when you rename a tab or move it. Adding an exam
means adding a row to `list_tabs.ktr`.

### Parent job — `gsheets_to_postgres.kjb`

Job parameters (**Edit → Settings → Parameters**):

| Parameter | Example |
| --- | --- |
| `SA_KEY` | `/home/pdc/PDC-Demo/secrets/gsheets-sa.json` |
| `SPREADSHEET_ID` | `1AbC…xyz` |
| `TARGET_SCHEMA` | `public` |
| `TARGET_TABLE` | `exam_results` |
| `WORK_DIR` | `/tmp/gsheets` |

Entries, connected in order on the success hop:

1. **Start**
2. **Create a folder** — `${WORK_DIR}`, *Fail if folder exists* cleared.
3. **Shell** — *Insert script*:
   ```sh
   python3 ~/PDC-Demo/secrets/gsheets-token.py "${SA_KEY}" "${WORK_DIR}/token.csv"
   ```
   (Windows host: `python` and a `.bat`-style path.) One token covers
   every tab in the run.
4. **Transformation** → `set_token.ktr` (below) — loads the token into the
   `GS_TOKEN` variable.
5. **Table exists** — connection `lab_postgres`, schema `${TARGET_SCHEMA}`,
   table `${TARGET_TABLE}`.
   - **true** hop → **SQL** entry: `TRUNCATE ${TARGET_SCHEMA}.${TARGET_TABLE};`
     (tick *Use variable substitution*), then on to step 6.
   - **false** hop (first run, table not created yet) → straight to step 6.

   The table is emptied **once here**, not in each tab's load, so each
   exam's rows are appended and one tab can't wipe another.
6. **Transformation** → `list_tabs.ktr` (below) — outputs one row per exam.
7. **Job** → `load_tab.kjb` (below):
   - **Options tab:** tick *Execute for every input row*.
   - **Parameters tab:** `EXAM` ← stream column `exam`,
     `SHEET_GID` ← stream column `gid`. Tick *Pass all parameter values
     down to the sub-job*.
8. **Success**. Add a failure hop from any entry to **Abort job** (or a Mail
   entry) so a revoked share or expired key is visible.

### `set_token.ktr`

**CSV file input** (`${WORK_DIR}/token.csv`, header row, one String field
`token`) → **Set variables** (field `token` → variable `GS_TOKEN`, scope
*Valid in the root job*, so `load_tab.kjb` can see it too).

### `list_tabs.ktr`

**Data Grid** with two String columns, `exam` and `gid`, and one row per
tab (the table above) → **Copy rows to result**.

### Sub-job — `load_tab.kjb`

Parameters: `EXAM`, `SHEET_GID` (empty defaults). Entries:

1. **Start**
2. **HTTP** (*Get a file with HTTP*):
   - **URL:** `https://docs.google.com/spreadsheets/d/${SPREADSHEET_ID}/export?format=csv&gid=${SHEET_GID}`
   - **Target file:** `${WORK_DIR}/sheet_${SHEET_GID}.csv`
   - **Headers tab:** `Authorization` = `Bearer ${GS_TOKEN}`
3. **Transformation** → `load_sheet.ktr`.
4. **Success**.

### `load_sheet.ktr`

1. **CSV file input** — file `${WORK_DIR}/sheet_${SHEET_GID}.csv`,
   delimiter `,`, enclosure `"`, *Header row present*, encoding `UTF-8`.
   The first time, point it at one downloaded tab, click **Get Fields**,
   then fix the types (Sheets exports everything as text: set dates to
   `Date` with the sheet's format, scores to `Number`).
2. **Get variables** — add field `exam` (String) = `${EXAM}`, so every row
   records which tab it came from.
3. **Select values** *(optional)* — rename headers to snake_case column
   names (`Email Address` → `email`).
4. **Table output** — connection `lab_postgres`, target schema
   `${TARGET_SCHEMA}`, target table `${TARGET_TABLE}`, *Truncate table*
   **cleared** (the parent job already emptied it), commit size `1000`.
   Click **SQL** once to generate and run the `CREATE TABLE`.

### Tabs with different columns

`load_sheet.ktr` reads a fixed set of columns, so it only works when every
tab has the same headers. If an exam's tab has different questions or
columns, give that exam its own table instead:

- Add a third column, `table`, to the Data Grid in `list_tabs.ktr`, and
  pass it to `load_tab.kjb` as `TARGET_TABLE`.
- Make one copy of `load_sheet.ktr` per distinct column layout (each with
  its own **Get Fields**), with *Truncate table* **ticked**.
- Drop step 5 (the truncate) from the parent job.

## 5. Run it

From Spoon, or headless on the VM:

```sh
./kitchen.sh -file=gsheets_to_postgres.kjb \
  -param:SA_KEY=$HOME/PDC-Demo/secrets/gsheets-sa.json \
  -param:SPREADSHEET_ID=1AbC...xyz \
  -param:TARGET_SCHEMA=public -param:TARGET_TABLE=exam_results \
  -param:WORK_DIR=/tmp/gsheets
```

Check the load from `data_sources/lab`:

```sh
docker exec -it demo-postgres psql -U demo_admin -d pentaho_exams \
  -c "SELECT exam, count(*) FROM public.exam_results GROUP BY exam"
```

Schedule it with cron (VM) or Task Scheduler (Windows host) calling
`kitchen` if the sheet changes regularly.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| HTTP entry gets **404** or an HTML login page | Sheet not shared with the service account email, or wrong spreadsheet ID |
| **403** | Drive API not enabled in the key's project |
| **401** after it used to work | Key deleted/rotated — create a new JSON key |
| Only the first tab arrives | Wrong or missing `gid` — copy it from the tab's URL |
| An exam is missing or appears twice | Its row in `list_tabs.ktr` is missing or duplicated, or two rows share a gid |
| Only the last tab's rows are left | *Truncate table* is ticked in `load_sheet.ktr`; clear it (the parent job empties the table once) |
| `permission denied for schema` | Connection is using `pdc_user`; switch it to `demo_admin` |
| Garbled accents | CSV file input encoding not `UTF-8` |
