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

## 4. The PDI job — `gsheets_to_postgres.kjb`

Job parameters (**Edit → Settings → Parameters**):

| Parameter | Example |
| --- | --- |
| `SA_KEY` | `/home/pdc/PDC-Demo/secrets/gsheets-sa.json` |
| `SPREADSHEET_ID` | `1AbC…xyz` |
| `SHEET_GID` | `0` |
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
   (Windows host: `python` and a `.bat`-style path.)
4. **Transformation** → `set_token.ktr` (below) — loads the token into the
   `GS_TOKEN` variable.
5. **HTTP** (*Get a file with HTTP*):
   - **URL:** `https://docs.google.com/spreadsheets/d/${SPREADSHEET_ID}/export?format=csv&gid=${SHEET_GID}`
   - **Target file:** `${WORK_DIR}/sheet_${SHEET_GID}.csv`
   - **Headers tab:** `Authorization` = `Bearer ${GS_TOKEN}`
6. **Transformation** → `load_sheet.ktr` (below).
7. **Success**. Add a failure hop from any entry to **Abort job** (or a Mail
   entry) so a revoked share or expired key is visible.

### `set_token.ktr`

**CSV file input** (`${WORK_DIR}/token.csv`, header row, one String field
`token`) → **Set variables** (field `token` → variable `GS_TOKEN`, scope
*Valid in the root job*).

### `load_sheet.ktr`

1. **CSV file input** — file `${WORK_DIR}/sheet_${SHEET_GID}.csv`,
   delimiter `,`, enclosure `"`, *Header row present*, encoding `UTF-8`.
   Click **Get Fields**, then fix the types (Sheets exports everything as
   text: set dates to `Date` with the sheet's format, money to `Number`).
2. **Select values** *(optional)* — rename headers to snake_case column
   names (`Email Address` → `email`).
3. **Table output** — connection `lab_postgres`, target schema
   `${TARGET_SCHEMA}`, target table `${TARGET_TABLE}`, *Truncate table*
   checked (full refresh each run), commit size `1000`. Click **SQL** once
   to generate and run the `CREATE TABLE`.

For several tabs, add one `SHEET_GID`/`TARGET_TABLE` pair per tab: either
copy entries 5–6, or drive the job from a small **Data Grid** of
`gid,table` rows with the *Execute for every input row* option.

## 5. Run it

From Spoon, or headless on the VM:

```sh
./kitchen.sh -file=gsheets_to_postgres.kjb \
  -param:SA_KEY=$HOME/PDC-Demo/secrets/gsheets-sa.json \
  -param:SPREADSHEET_ID=1AbC...xyz -param:SHEET_GID=0 \
  -param:TARGET_SCHEMA=public -param:TARGET_TABLE=exam_results \
  -param:WORK_DIR=/tmp/gsheets
```

Check the load from `data_sources/lab`:

```sh
docker exec -it demo-postgres psql -U demo_admin -d pentaho_exams \
  -c "SELECT count(*) FROM public.exam_results"
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
| `permission denied for schema` | Connection is using `pdc_user`; switch it to `demo_admin` |
| Garbled accents | CSV file input encoding not `UTF-8` |
