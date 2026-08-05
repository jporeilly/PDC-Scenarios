# Workshop — Automating the Glossary Workflow with the PDC Public API

*Copper State Credit Union scenario · PDC 11.0.0 · Technical Track Module 01*

**Primary role:** Solution Architect / Developer
**Estimated time:** 75–90 min
**App version:** Glossary Generator 1.21.0

> **Audience.** The Architect / Developer learning path. Assumes the UI-driven
> workshops are complete — you should already have built the CSCU business
> glossary and run profiling by hand. This session is the payoff: *you have done
> this in the UI; here is the automated path, and here is exactly which calls it
> makes.* Doing it manually first is what makes the API legible.

> **You will build.** An end-to-end, token-driven pipeline that resolves, writes,
> scores and compares glossary metadata in PDC over the public API.

## About this workshop

Every other workshop in the set teaches Pentaho Data Catalog through its UI.
This one is different: it teaches the **PDC Public API** by driving it from a
companion tool — the **Glossary Generator** — that walks the whole glossary
workflow on one screen: connect, review, govern, apply. You will see the same
outcomes you produced by hand, this time executed over HTTP.

> **Custom tool, not a product feature.** The Glossary Generator is a reference
> implementation built for this course. Buttons like *Apply to PDC*, *dry-run*
> and *Compare with PDC profiling* are app features that call public PDC
> endpoints. They are **not** Data Catalog UI features. Pentaho Data Catalog is
> the product; the app is the on-ramp.

### Before you begin — install and connect

If the app is not already running on your lab VM, follow its `INSTALL.md`. The
app runs **natively** — there is no container image:

| Host | Command |
| --- | --- |
| Linux / macOS | `./run.sh` |
| Windows (PowerShell) | `.\run.ps1` |
| Windows (cmd) | `run.bat` |

Each launcher boots uvicorn and serves the React UI plus interactive API docs at
`/docs`. Set `GLOSSARY_COMPANY` and `GLOSSARY_DOMAIN_PACK` for the Copper State
vocabulary before starting. Then open **Apply → PDC connection**, enter your PDC
base URL and version, and click **Get token**.

> **Use the vhost, not the IP.** PDC's proxy routes by hostname. Give the app
> `https://pentaho.io` (or whatever vhost your instance answers on), never a bare
> `https://192.168.1.x`. The public API tolerates an IP, but PDC's internal API —
> which the object-store file scan needs — returns a bare `401 Unauthorized` on
> one, with a valid token. The app now names this cause in the error rather than
> leaving you to guess.

The token is held **in memory only**; an admin or Business Steward account is
enough.

## Learning objectives

- Authenticate to PDC, obtain a bearer (JWT) token, and read the role and expiry
  it carries.
- Explain the one hard boundary of the API: **the glossary is created by import;
  the API only updates existing entities**.
- Resolve business-term and column entity ids through the search and
  `entities/filter` endpoints.
- Merge and write term links, sensitivity, CDE and verified-lineage onto columns
  with `PATCH`, safely, using a dry-run.
- Apply a mapping policy so only the right terms — CDEs, PII and evidence-backed
  columns — are linked, instead of every scanned column.
- Trigger **Calculate Trust Score** as a job and poll it to completion.
- Pull PDC's own profiling statistics and compare them against the app's discovery.
- Trigger a **Data Discovery** job to profile object-store documents, and know
  where Data Quality comes from for files versus database columns.

## Overview — the challenge, the goal, and the two apps

In PDC the same three facts about a column — which business term it maps to, what
tags it carries (like PII), and how sensitive it is — get decided in more than one
place, by hand, at different times. The Data Identification method stamps tags on a
match, the glossary term carries its own tags, and the steward judges sensitivity.
Nothing forces them to agree, because tags are free text on both sides. The result
is drift between the glossary and the methods, mis-graded sensitivity (a member id
guessed LOW when it should be HIGH and PII), and inconsistent tags with no
compliance context — so a classification is hard to trust, keep consistent, or
defend in an audit.

The goal is to build a **Registry**: one list, one row per concept, holding the
single agreed answer for that concept — its business term (and PDC term id), its
governed tags from a controlled list, its sensitivity decided by rule, its
category, verified compliance links, and how to build its Data Identification
method. Everything downstream is generated from that one row, so the glossary term
and the method tags cannot disagree, and a linter catches any deployed method that
drifts.

### Two apps, one handoff

The Registry is the contract between two separate apps, used in order — and keeping
them distinct matches PDC's own separation of the Business Glossary from Data
Identification.

1. **Glossary Generator (first)** builds the business glossary: it scans sources,
   proposes candidate concepts, lets the steward review them, and exports the
   glossary for import into PDC, which mints the term ids. In doing so it authors
   the Registry — the concepts, their governed tags, sensitivity, and references —
   saved alongside the glossary.
2. **Policy Generator (next)** builds the Data Identification policy: it reads the
   Registry with the reconciled term ids and emits the methods — dictionaries
   (imported as ZIPs of JSON + CSV) and patterns (JSON), each bound to its term and
   stamping the Registry's tags. This creates the policy, keeps tagging consistent,
   fills coverage gaps, and flags any method that has drifted.

> **A note on the word *policy*.** In PDC there is no separate Policy object. A
> Data Identification policy is simply the combination of dictionary and pattern
> methods a steward chooses to enable. The Policy Generator builds those methods;
> the steward's selection is the policy.

## The workflow, consolidated

The app's four steps — connect, review, govern, then resolve & apply — expand into
this pipeline. The crucial column is the last: **where each step actually runs**.
One step is UI-only by necessity; the rest are public-API calls the app makes for
you.

| # | Step | App action | Runs as |
| --- | --- | --- | --- |
| 1 | Connect & scan | Scan the source, suggest terms | Local (app) |
| 2 | Review & prune | Prune to the terms you want | Local (app) |
| 3 | Govern & generate | Export import-ready glossary | Local (app) |
| 4 | Import the glossary | — (done in PDC UI) | PDC UI · Actions → Import |
| 5 | Get token | Authenticate to PDC | API · `/auth` |
| 6 | Resolve term ids | Look up each term's id + glossaryId | API · `/search` |
| 7 | Apply to PDC | Resolve column, merge, write | API · `/entities/filter` + `PATCH` |
| 8 | Score & compare | Trust score; app-vs-PDC profiling | API · `/jobs` + `/profiling-info` |

> **The golden rule.** Step 4 is **import-only**. There is no "create term"
> endpoint in the public API. You import the glossary through the UI (JSON Lines
> or CSV), and only then can the API attach those terms to columns — because the
> API works by *updating entities that already exist*. That is why the order is
> **import → resolve → apply**, never apply-first.

## Where this fits in PDC's processing order

The app does not replace PDC's data-scanning stages — it layers governance on top
of them. Knowing which is which is what tells you the safe order.

| PDC's data scan owns — run first | The app writes — layered on top, over the API |
| --- | --- |
| **Metadata ingest** — schema, tables, columns, keys | **Glossary terms** — the term↔column links |
| **Data Profiling** — stats + intermediate data (bitsets, HLL, pattern analysis, DQ pre-analysis); feeds foreign-key detection and data flow | **Stewardship** — steward / owner / custodian |
| **Data Identification + PII** — dictionary / pattern tags and auto-sensitivity; requires profiling first | **Governance flags** — sensitivity confirm/override, CDE, verified-lineage, rating, manual quality score |
| | **Trust Score** — the calculate-trust-score job, run last |

**Recommended order:** Ingest → Profile → Identify (+ PII) → import the glossary →
Resolve → Apply → Calculate Trust Score (last).

> **Why the order matters.** Profiling and identification re-derive the
> data-scanned fields — tags, classification, data quality — from the actual data.
> Run them *after* the app and they overwrite what you set; run them *first* and
> the app's Apply merges its governance on top. Trust Score is computed from Data
> Quality, Ratings, Lineage, Classification and whether a glossary term is
> assigned, so it must be calculated **last**.

---

# Part 1 — Build the glossary in the app

Before a single API call, the Generator does its real work locally: it connects to
your sources, scans them into candidate terms, lets a steward review and prune
those terms, then bakes in stewardship and exports an import-ready glossary. These
are steps 1–3 — all **Local (app)** — and they produce the JSONL you import in
step 4 and apply over the API in Labs A–F. Get these three right and the API half
is mechanical.

> **The scan step has two lanes.** Structured and unstructured data share one
> processing spine — they differ only at the scan. A database is described by its
> schema, so PDC *profiles* it; a bucket of files has no schema, so PDC *discovers*
> it. The Generator mirrors that split, then **Add to glossary** merges both lanes
> into a single glossary. At CSCU the `cscu_core` database takes the profiling lane
> and the `cscu-documents` object store takes the discovery lane — one glossary,
> spanning both.

## Step 1 · Connect the sources and scan

**Goal.** Register each source, scan one to start, then *Add to glossary* from the
rest so a single glossary spans structured and unstructured data.

The **Connect** page holds one connection per source. The app reads your data with
whatever credentials you give it, so **give it read-only ones** — it never writes
back to a source.

| Connection | What it reads | Notes |
| --- | --- | --- |
| **Database (live scan)** | Schema, keys and comments; sampling refines sensitivity and data quality | PostgreSQL / MySQL / SQL Server, read-only. Set the schema on the connection (e.g. `cscu_core`) |
| **Object store (MinIO / S3)** | Browses a bucket over the S3 API; each file becomes a document term | Use the host / VM IP for the endpoint, not `localhost` |
| **DDL file** | Parses a `CREATE TABLE` script — same suggestions, no live connection | For when you cannot reach the database |

### Three ways to get connections in

1. **Bulk-load into PDC.** The *Bulk-load data sources into PDC* card takes a CSV
   (per row: `kind`, and either host/port/database/schema for a database or
   endpoint/region/bucket/keys for an object store) and, for each row, creates the
   data source in PDC and triggers its ingest. A source that already exists is
   detected and shown as **EXISTS** (re-scanned, not re-created), so re-runs do not
   hit a duplicate error.
2. **Harvest from PDC.** Lists what PDC has already catalogued and pulls the
   glossary straight from that metadata — table columns for a database, files for
   an object store. Because it reads PDC's catalog, it needs no re-created
   connection and no database password.
3. **Add to app connections.** The same CSV can populate the app's own connections
   — these drive the Schema diagram, the Files browser, Test and live-scan. The app
   runs as a host process, so set a reachability remap as you import (e.g.
   `192.168.1.200=localhost`, `5432=5433`).

> **Two vantage points.** The same source needs different host values depending on
> who connects. PDC resolves the service names in the CSV; the app is a host
> process and needs a host-reachable address. The MinIO endpoint, being an IP,
> usually works for both — which is why only the database needs a remap.

> **Object stores are file systems.** PDC registers an AWS S3 / MinIO bucket with
> `databaseType = AWS` (a file system), not a database type. **Profile / discover**
> on an object store now triggers the *file scan first*, then Data Discovery —
> because Discovery does not crawl a bucket, it analyses what a file scan has
> already catalogued. Without the ingest there are zero file entities and Discovery
> has nothing to do, which is why an object store used to come back `profile=FAIL`
> while the database profiled fine. One control now does the whole job.

### What a scan turns up

A scan is not a name-matching guess — it reads structure and samples to produce
evidence. From one pass it derives, per column:

- **One term per column** — every column becomes a candidate, so review is
  *pruning*, not gap-hunting.
- **Definitions and purpose** — drafted locally from names, comments and keys.
- **Sensitivity and PII** — HIGH / MED / LOW with PII categories, inferred from
  names and samples.
- **CDE and keys** — reads primary/foreign keys and infers Critical Data Elements
  for the steward to confirm.
- **Data quality** — profiles distribution, uniqueness and patterns.
- **A physical model** — keys and foreign-key edges from *all* columns, kept or
  pruned, so the join graph survives pruning (see below).

### Under the hood — what a scan actually calls

The scan never touches PDC's public API. It reads your sources directly and writes
local JSON; the two lanes just speak different protocols. Nothing here writes.

**Database lane — SQL over `information_schema`:**

```sql
SELECT table_name, column_name, data_type, ordinal_position,
       (is_nullable = 'NO')
  FROM information_schema.columns
 WHERE table_schema = :schema
 ORDER BY table_name, ordinal_position;
-- primary & foreign keys: pg_catalog on PostgreSQL,
-- information_schema.key_column_usage fallback elsewhere
```

Then a bounded per-column sample refines sensitivity, PII and the data-quality
dimensions — evidence, not name guesses.

**Object-store lane — S3 API (boto3, path-style, SigV4):**

```text
list_objects_v2(Bucket, MaxKeys=1)            # test: bucket reachable?
get_object_tagging(Bucket, Key)               # test: does tagging work?
get_bucket_tagging(Bucket)                    # bucket-level owner tag
list_objects_v2(Bucket, Prefix) <paginated>   # walk every object -> folders
head_object(Bucket, Key)                      # x-amz-meta-* owner fallback
head_object / get_object                      # metadata + content preview
```

> **The in-app panels are authoritative.** Every stage has an expandable *Under the
> hood* panel with a **View source** button — Connect shows the database SQL, Files
> shows the S3 API, Review shows the local transforms (which issue no calls at
> all), and Apply shows the full PDC choreography. Those panels are always current;
> this guide is a snapshot.

## Step 2 · Review & prune the candidate terms

**Goal.** Every column is already a candidate term — so you refine and prune, you
never hunt for gaps.

Open **Review**. Each row is a candidate term with a definition, purpose,
sensitivity, tags and a confidence level. The working order is printed on the page
itself (*How to review — the working order*), and it is: prune → name the glossary
→ run the AI pass → resolve duplicates → approve the pending vocabulary.

### Structural keys arrive already pruned

A surrogate primary key or a foreign-key reference id is not a business term. The
scan auto-prunes those, badges them **KEY**, and explains why on the row — ticking
**Keep** restores any of them. The PK/FK relationship is *not* lost: it travels to
the Registry's **physical model**, built from every column whether kept or pruned.
This mirrors the physical-versus-glossary layering that Actian and Collibra use —
the join graph is infrastructure, the glossary is meaning.

### The AI pass — one agent, not a toolbar of them

The single grid agent is **AI pass (all fields)**. In *one model call per batch of
kept rows* it returns:

| Field | Behaviour |
| --- | --- |
| Definition | rewritten, grounded in the row's scan evidence |
| Purpose | why the business keeps the data — not a restatement of the definition |
| Name | a clearer business term, offered as a **→** chip; never overwrites your Term |
| Tags | **only** from the governed allow-list |
| Category | filled **only** when the current one is blank |
| Sensitivity / PII | **never set by the model** — deterministic from the scan |

Expand a row and click **AI review** to run the same pass on that row alone — same
prompt, same evidence, same guardrails, for when one term came back weak and a full
sweep is not worth the minutes.

> **Why one agent.** Enrich, AI suggest, AI categorize and an AI QA judge were
> separate buttons until 1.15.0. They swept the same rows and overlapped on name /
> category / tags, so the last one silently overwrote the others — and each
> restated the guardrails in its own wording, so they drifted apart. Consolidating
> them also made the pass ~2.2× faster than the passes it replaced, and batching
> turned a 120-row scan from ~120 model calls into ~20.

**The definition linter rides along, free.** Before the model runs, a deterministic
linter flags circular, echoed, vague, too-short, copy-pasted and *templated*
definitions — including the scan's own fallback sentences ("Severity associated
with an account alert record"), which read like prose but say nothing specific.
Each flag is fed into the prompt as a **rewrite order**, so the pass returns a
specific sentence instead of boilerplate. Rows are **re-linted afterwards**, so a
surviving QA ⚠ chip means the model could not improve that definition from the
available evidence — a real signal, not repeat noise. Because it is deterministic,
it still works with the LLM offline.

> **Agents propose; the steward accepts.** Results land as **inline
> click-to-accept pills** on the affected cells, batch by batch while the run
> streams. The grid never mutates mid-run. Accept a pill to take just that change,
> or **Accept all / Dismiss all** from the strip above the grid. The **LLM**
> provenance pill appears only *after* a proposal is accepted — so provenance stays
> truthful.

**The model is not required.** Point the app at a local **Ollama** model, or at a
hosted provider (Anthropic, OpenAI, Azure OpenAI, Google) on the **Settings** page.
Hosted API keys are session-only by design — held in process memory, never written
to `settings.json`, so a State snapshot cannot leak billing credentials. Persist one
by exporting the provider's environment variable instead.

### Merge duplicates & auto-disambiguate

Because the scan turns every column into its own candidate, two moves tidy the list
— one folds terms together, the other keeps them apart:

- **Merge duplicates.** The same concept shows up in many columns — `member_id` in
  accounts, cards and loans — so the scan proposes the same term repeatedly. Merge
  folds them into a single governed term linked to every column that implements it:
  the *one term, many data elements* shape a real glossary wants.
- **Auto-disambiguate.** The opposite hazard: two columns sharing a name that mean
  different things — `status` on an account versus `status` on a loan. Left
  unchecked a merge would fuse them into one wrong term. Disambiguate names them
  distinctly (*Account Status* versus *Loan Status*).

Each duplicate group carries its own recommendation with the reason — a foreign key
between the columns, matching or conflicting induced formats, overlapping or
disjoint code lists. **AI advise** escalates only the ambiguous groups by sampling
live values over your connection. Every control is reversible; **Reset all** returns
the grid to the raw scan.

> **Run the AI pass *before* resolving duplicates.** Final names dissolve false
> duplicates (a rename *is* disambiguation), and real definitions make the
> remaining same-name calls easy.

### How confidence is set

Confidence is a triage signal — how much evidence backs a suggestion — not a verdict:

- **High** — a database comment or a key backs the column.
- **Medium** — inferred from the column name plus its type.
- **Low** — templated from the name alone.

Raise it at the source (add column comments) or by enhancing against a curated
glossary. Triage by it; do not treat Low as wrong or High as final.

> **Terms export as Draft.** Nothing here is approved. Every term leaves the app as
> a **Draft** — a proposal, not an approved definition. A Business Steward approves
> them in PDC after import. Careful review here is exactly what makes that approval
> fast.

## The Term & Tag Dictionary — one governed vocabulary

**What it is.** The **Dictionary** page governs the vocabulary that tagging and
term-naming draw from — a generic baseline of common terms and tags, plus a company
layer seeded from your domain pack and grown, under review, from every scan. It is
the controlled allow-list: a term is only tagged with tags that live here.

**Why it is not the same as the glossary's tags.** Setting a tag on a term
describes *that one concept*. A Policy Generator method is a rule PDC runs during
Data Identification to find and tag data automatically across the whole estate —
columns you never mapped, tables that arrive next month, unstructured files. The
dictionary is what keeps them speaking the same language: it is embedded in the
Registry at export, so the Policy Generator's Assign-Tags actions can only use the
same allow-list the glossary uses. **That is the tag-consistency contract between
the two apps.**

### Two layers, and an approval gate

| Layer | What it holds | Editable? |
| --- | --- | --- |
| **Generic (baseline)** | Common terms and tags with sensible sensitivity — Member ID, Account Number, Email, SSN, Amount — plus baseline tags with sensitivity floors | Protected — cannot be removed |
| **Company** | Terms and tags specific to this deployment, seeded from the `credit_union` domain pack and accreted from scans | Yes — steward-owned |

New terms and tags a scan turns up **do not govern anything yet** — they land in
*Pending steward review*. Only when a steward approves them do they enter the
governed vocabulary and reach the Registry.

### What you do on the Dictionary page

1. **Set who you are.** Enter a name in *Acting as* before you approve, reject or
   save. Every governance action is written to the audit trail with that name and a
   UTC timestamp.
2. **Clear the pending queue.** Approve what belongs in the company vocabulary and
   reject the noise; until you do, those items are excluded from the Registry and
   the search facets.
3. **Curate the terms.** Layer, Sensitivity, Aliases (divergent names that resolve
   to one term), Tags and a Used count.
4. **Curate the tags.** Each tag has a **Floor** (the sensitivity it raises a term
   to), a Used count and example terms. Keep this list tight — every tag becomes a
   method the Policy Generator can emit and a facet in PDC.
5. **Add rules.** A rule is a regex matched against a term's name plus the tags to
   apply — how a whole domain gets tagged at once
   (e.g. `sar|suspicious|bsa|aml → compliance;sensitive`).
6. **Preview the search facets.** Shows how each governed tag will look as an
   OpenSearch facet, sized by reviewed usage. Retire empty tags and merge
   near-duplicates *before* methods deploy — cheap to fix here, expensive once live.
   Empty means *no reviewed app usage yet*, never "retire everything".
7. **Check the audit trail.** Append-only, actor and timestamp per decision. A
   summary is embedded in the Registry at export.
8. **Save / Reload / Export / Reseed.** Reseed rebuilds the vocabulary from the
   baseline plus the current domain pack — run it after editing `domain_pack.json`,
   then re-run the **AI pass** so the new rules reach the rows.

> **Aliases and the sensitivity lift.** Aliases resolve divergent names to one
> canonical term *at scan time*, so a `cust_id` column and a `member_account_number`
> column both become **Member ID** and collapse into one mergeable term.
> Sensitivity is **ordinal**: a term is raised — never lowered — to the highest
> floor implied by its tags and its canonical term. The dictionary can only tighten
> a classification.

## Step 3 · Govern & generate the JSONL

**Goal.** Assign who owns each term, bake stewardship into the export, and generate
an import-ready JSONL glossary for PDC.

- **Build the roster.** Add people by hand, or fetch the live roster from Keycloak
  so names and accounts match the target instance.
- **Assign stewardship.** Steward, owner, custodian, status, rating and
  reviewed-date — globally, or per category where ownership differs.
- **Bind people to PDC.** Each person resolves to a PDC account by **UUID**. UUIDs
  are per-instance, so fetch the roster from the Keycloak of the instance you will
  import into.
- **Generate and import.** *Generate import JSONL* writes one JSON line per
  glossary, category and term, with steward/owner UUIDs baked in. Import it via PDC
  **Business Glossary → Import**.

```json
{"type":"glossary","name":"Copper State", ...}
{"type":"category","name":"Member","glossary":"Copper State", ...}
{"type":"term","name":"Member Name","glossary":"Copper State","category":"Member",
 "steward":"<uuid>","owner":"<uuid>","status":"DRAFT", ...}
```

> **The import is whole-glossary.** PDC's import **replaces** the entire glossary,
> not a delta. To update in place on a re-run rather than create duplicates, reuse
> the same `_id`s across regenerations — the same discipline the API side relies on
> when it resolves term ids (Lab B). If terms were *renamed*, delete the old
> glossary first: ids are name-based, so renames mint new terms.

> **Why bind by UUID, not name.** People and terms link to PDC by per-instance
> UUID, never display name. Fetching the roster from the target Keycloak guarantees
> the steward and owner references resolve at import.

### Draft policies (AI) — the Quality layer

*Generate* also writes the **Registry** (`registries/registry.<glossary>.json`),
and **Draft policies (AI)** turns its detection seeds into ready-to-import PDC
pattern/dictionary rule files. Alongside the glossary and detection layers it emits
**`Quality/` DQ-expectation rules**, derived without guesswork:

| Rule | Derived from |
| --- | --- |
| `format` | the induced regex |
| `allowed_values` | the profiled value list |
| `not_null` / `unique` | measured baselines from the scan |
| `valid_date` / `numeric` | the column's persisted physical type |

These matter most where the rules actually run — extracts and landing zones, where
the engine no longer enforces types.

---

# Part 2 — The PDC Public API

With the glossary generated and imported through the PDC UI, the term↔column links
can finally be written — because the API only ever updates entities that already
exist.

## Authentication and the JWT

Every protected endpoint expects `Authorization: Bearer <token>`. Two equivalent
ways to get one:

```http
POST /api/public/v2/auth        (application/x-www-form-urlencoded)
username=<user>  password=<pwd>  client_id=pdc-client
grant_type=password  scope=openid profile email

200 -> { "data": { "accessToken": "eyJhbGciOi..." } }
```

```http
POST /keycloak/realms/pdc/protocol/openid-connect/token
client_id=pdc-client  grant_type=password
username=<user>  password=<pwd>
```

> **Token facts that matter.** The token is time-limited — long runs must
> re-authenticate when it expires (the app re-auths on a 401). `admin` /
> `system_administrator` works for everything; a **Business Steward** is enough for
> glossary edits and is the safer least-privilege choice. Never persist the token.

## The endpoint map

| Group | Endpoint(s) | Used for |
| --- | --- | --- |
| Auth | `POST /auth` | Obtain the bearer token |
| Search | `POST /search` | Find a term → its id + glossary |
| Entities | `POST /entities/filter` | Find a column entity by name / fqdn / parent |
| Entities | `PATCH /entities/{id}` | Write businessTerms + features onto a column |
| Entities | `POST /entities/filter/profiling-info` | Pull PDC's profiling stats |
| Jobs | `POST /jobs/execute/calculate-trust-score` | Compute Trust Score |
| Jobs | `POST /jobs/execute/data-discovery` | Profile object-store files & folders |
| Jobs | `GET /jobs/{id}/status` | Poll a running job |

> **Versioning (v2 vs v3).** Paths carry a version segment. Entity and search
> shapes are stable across v2/v3; the jobs surface is richest in **v3**, which is
> PDC 11's native version and the app's default for new installs. In v3 the app
> goes straight to `POST /jobs/execute/bulk` — the per-job paths do not exist
> there. Your instance's Swagger is the source of truth. The entities filter is
> clamped to `size<=500`, which the API enforces, and the pagination cursor is a
> **query parameter**, not a body field.

## Lab A — Authenticate

**Goal:** obtain a token and confirm you are who you think you are before writing.

**In the app.** Open **Apply → PDC connection**. Fill the base URL, version, and
your username / password, then click **Get token**. The app authenticates and
reports who the token belongs to — roles and expiry — *before anything writes*.
Every later call in the run reuses that token.

**What to verify.** The expected role badge is present, and the expiry gives you
enough runway for the apply run.

```bash
curl -sk -X POST https://<host>/api/public/v2/auth \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode username=<user> --data-urlencode password=<pwd> \
  --data-urlencode client_id=pdc-client \
  --data-urlencode grant_type=password \
  --data-urlencode 'scope=openid profile email' | jq -r .data.accessToken
```

## Lab B — Resolve term IDs

**Goal:** turn the term names in your export into the per-instance ids PDC needs.
This is why the glossary must be imported first — a term has no id until it exists.

**In the app.** With the glossary imported, click **2 · Resolve term IDs**. The app
searches each term and stamps its `id` and `glossaryId` into the Data Elements JSON.
Unresolved names are reported — usually the import has not run, or the name differs.

```http
POST /api/public/v2/search        Authorization: Bearer <token>
{ "searchTerm": "Member Name", "searchFacets": { "type": ["term"] } }

// a term hit carries its own _id (the term id) and
// rootId (the glossary it belongs to = glossaryId)
```

> **Order matters.** Import → Resolve → Apply. Apply depends on Resolve having
> stamped real ids; the app will warn and let you proceed by name, but a write with
> real ids is the clean path.

## Lab C — Apply to PDC

**Goal:** write each kept term link — plus sensitivity, CDE and verified-lineage —
onto its column, without clobbering anything already there. **Always dry-run first.**

### Which terms get written — the mapping policy

The app does not link every term. Linking every column pollutes lineage, search and
impact analysis, and does nothing for the Trust Score, whose glossary-term input is
binary. A term is written only when it clears a relevance bar:

- **Mapped automatically:** Critical Data Elements, PII columns, and terms with real
  evidence — a DDL comment, a key, or a profiling hit (High or Medium confidence).
- **Held back:** low-confidence terms templated from a column name alone, and
  conceptual or governance terms with no physical column.
- **Steward override wins:** a per-row *Map = Yes/No* always beats the policy.
- **Tunable:** Selective (CDE · PII · High/Medium, default), Strict (CDE · PII ·
  High only), or Map everything (legacy).

> **Map by business value, not volume.** The Data Elements step reports mapped vs
> held-back counts and lists every term it withheld and why — the selectivity is
> visible, not silent.

### How a column write works

1. **Resolve the column entity** — filter to find its `_id`.
2. **Read what is there** — the column may already carry business terms and features.
3. **Merge, do not replace** — union the new term(s) with the existing ones.
4. **PATCH the superset.**

> **Why the app sends the whole merged array.** The PATCH contract is explicit:
> **array fields fully replace**, scalar fields overwrite, object fields merge only
> the keys you send. Because `businessTerms` is an array, sending just the new term
> would drop the existing ones.

```http
POST /api/public/v2/entities/filter?extended=true&size=500
{ "filters": { "fqdns": ["cscu_core.members.member_name"], "types": ["COLUMN"] } }
```

```http
PATCH /api/public/v2/entities/<column _id>
{ "attributes": {
    "businessTerms": [ {existing...},
      { "id": "<term id>", "glossaryId": "<glossary id>", "name": "Member Name" } ],
    "features": { "sensitivity": "HIGH",
                  "isCriticalDataElement": true,
                  "isLineageVerified": true,
                  "rating": { "value": 4 } } } }
```

> **Valid `businessTerms` properties.** Each term is reduced to the keys PDC
> accepts: `id`, `glossaryId`, `name`, `sourceName`, `sourceType`,
> `confidenceScore`. Any extra field — notably the app-internal glossary display
> name — makes PDC reject the whole PATCH with a **400**.

**In the app.** Leave **Dry-run** ticked and preview: the results table shows, per
column, the resolved entity id, the current → merged term diff, and the exact PATCH
body. Nothing is written. When it looks right, untick Dry-run and **Apply to PDC**.

## Lab D — Calculate Trust Score

> **This computes a TABLE / FILE Trust Score, not a column one.** PDC scores tables
> and files, never columns.

Trust Score takes a Data Quality input. Lab C derived a per-column `qualityScore`
(0–100) from the scan — completeness, uniqueness (only where the column is meant to
be unique) and validity — plus a 1–5 rating, and PATCHed both onto the column.

| Entity | Scored? | How the app feeds it |
| --- | --- | --- |
| **Table** | Yes | Rolls each column's mean qualityScore + rating up here, then runs the job |
| **File** | Yes | Applies rating, DQ and term directly; the job runs here too |
| **Column** | No | Writes qualityScore + rating from the scan — inputs, not a score |
| **Folder** | No | Skipped — not a Trust Score target |

> **The app creates the table terms; the Steward links them.** The app writes one
> table-level term per table into the generated glossary (*Member Record*, *Loan
> Record*, …) so they are ready to use, but does not link them — the Data Steward
> links each to its table by hand to give that table's Trust Score its
> assigned-term input.

```http
POST /api/public/v3/jobs/execute/calculate-trust-score
{ "scope": [ "<table id>", "<table id>" ] }
// -> { data: { _id: "<job id>", workerName, activity } }

GET /api/public/v2/jobs/<job id>/status
-> { "status": "COMPLETED", "activity": ..., "duration": ... }
```

> **On the availability nuance.** A PDC user-doc says Trust Score is "not available
> in public API's", yet the v3 Swagger exposes a discrete `CALCULATE_TRUST_SCORE`
> endpoint. Because the doc and the Swagger disagree, the app submits it behind a
> toggle and reports exactly what your instance returns. In v3, bulk returns
> successes/failures and no job id, so status polling is skipped — watch PDC's
> Workers page instead.

## Lab E — Compare with PDC profiling

**Goal:** lay PDC's own profiling numbers next to the app's discovery, column by
column.

```http
POST /api/public/v2/entities/filter/profiling-info?sampleLimit=20
{ "filters": { "parentIds": ["<table id>"], "types": ["COLUMN"] } }

// each item -> profilingInfo.stats: cardinality, density, selectivity,
// uniqueness, nulls, blanks, zeros, min/max/avg value & length,
// lexicalMin / lexicalMax
```

**Reading the comparison.** Close agreement validates the app's heuristics; large
gaps usually mean PDC profiled a different sample, or the column has not been
profiled in PDC yet (shown as *not in PDC* — run Data Profiling on the table and
compare again).

## Lab F — Profile documents in PDC

**Goal:** have PDC profile the object-store files you just applied to, so documents
showing *Profiled Status: SKIPPED* gain PDC's own Data Quality.

> **Does the profiler also apply to a database source?** Yes, through a different
> front-end. A database column is profiled when you scan the database — the app
> samples live values. An object-store file has no table to sample, so the app reads
> the file's content (CSV / JSON / XML / text) for the same three dimensions. Both
> land a `qualityScore`; only the measurement differs. On the PDC side: **Data
> Discovery** profiles files and object stores; a database is profiled by
> structured **Data Profiling**.

```http
POST /api/public/v3/jobs/execute/data-discovery
{ "scope": [ "<folder / file entity id>", ... ],
  "configs": { "buildSamples": true, "headerExists": true,
               "ingestProperties": true, "computeChecksum": true,
               "withProfile": true } }        // withProfile is v3-only
```

**In the app.** Open **4 · Profile documents in PDC** after a non-dry-run apply and
click *Run Data Discovery on documents*. Re-run Lab E to see each file's new PDC
Data Quality next to the app's.

### Scope a folder, not a file — the cascade is the whole point

`scope` accepts any entity id, but **what you send changes how much gets profiled**:

| You scope | PDC profiles |
| --- | --- |
| A **FOLDER** entity | that folder **and every file inside it** — it cascades |
| A **FILE** entity | that one file, and nothing else |

This matters more than it looks, because a Data-Elements payload carries **one
representative file per folder** — the term's first `Source_Column`. Scope those
file ids and you profile five documents out of sixteen. The job still returns
**SUCCESS**, because it did exactly what you asked.

The app resolves each unique `(bucket, folder)` pair to its folder entity and
scopes those, falling back to individual files only when a folder cannot be
resolved. You can see which happened in the run message:

- `awc-documents/compliance` — **slashed**: folder scope, cascading.
- `awc-documents.compliance.epa_…pdf` — **dotted**: the file fallback. The app now
  warns when this happens, because the siblings will not be profiled.

> **The gotcha that caused this.** PDC types an object store's folders **`FOLDER`**,
> not `DIRECTORY` — a live file scan reports *"16 FILE + 5 FOLDER entities
> discovered"*. An entity filter that omits `FOLDER` gets **no folder hits at all**,
> because PDC filters them out server-side; the lookup then looks indistinguishable
> from *"that folder isn't catalogued"*. Fixed in Glossary Generator **1.17.1**. If
> you write your own client, put both type names in the filter.

### Reading the result — SKIPPED is not always a failure

Discovery does two different jobs, and only one of them applies to every file:

| File type | Properties & checksum | Profiled Status |
| --- | --- | --- |
| `.csv` `.tsv` `.json` `.jsonl` `.txt` | yes | **COMPLETED** — columns with row counts, cardinality, uniqueness, density, lengths |
| `.pdf` `.docx` | yes — pages, author, title, producer | **SKIPPED**, permanently |

A PDF has no rows or columns to sample, so profiling it is meaningless and PDC
skips it by design. It still gains its document properties and a checksum, and it
still carries its business term, sensitivity and rating. **`SKIPPED` on a PDF is
the correct outcome, not a broken run** — and neither the app nor PDC can ever
produce a Data Quality score for one.

> **Verify the cascade properly.** Check a file that was **not** the
> representative — e.g. `gis/pipe_network*.csv` when only `asset_inventory.csv` was
> scoped. If it comes back with columns and a *Last Successful Profiled Date*, the
> cascade reached it. Checking the representative only proves the scope, not the
> cascade; checking a PDF proves neither, since it can never profile.

---

# Alternative input — harvesting from PDC

The primary path is the full four-step workflow. **Harvesting** is the alternative
for when you cannot scan the source yourself: it builds the glossary from what PDC
has already catalogued — schema, data types, keys and, where stewards have done the
work, descriptions, sensitivity and trust scores. No database connection, no
password.

> **There is no "list all data sources" call.** The data-sources group is
> retrieve-by-id only; `GET /api/public/v2/data-sources` returns *Route not found*
> by design. So the app discovers harvestable roots from the catalog itself, with
> the same `entities/filter` endpoint Resolve and Apply use.

```http
POST /api/public/v2/entities/filter?extended=true
{ "filters": { "types": ["SCHEMA","DATA_SOURCE","RESOURCE"] } }
```

```http
POST /api/public/v2/entities/filter?extended=true
{ "filters": { "types": ["COLUMN"] } }     // scoped client-side to the chosen fqdn

// from each COLUMN entity the app reads:
//   metadata.column.dataType / isPrimaryKey / isForeignKey / isNullable
//   attributes.info.description      -> definition (high confidence)
//   attributes.features.sensitivity / trustScore
//   attributes.businessTerms[]       -> already-governed flag
```

**Read before you write.** Every column PDC already governs is flagged in the grid
with its current sensitivity, trust score and linked terms. The generator suggests
but never silently overwrites a steward's work — the same merge discipline Apply
uses, surfaced earlier in the pipeline.

### Harvest replaces an empty grid and merges into a loaded one

The order you do things in decides what you end up with:

| Grid before | **Harvest** does |
| --- | --- |
| empty | starts a fresh **unnamed** workspace — nothing autosaves until you name it, so a saved glossary cannot be damaged |
| a glossary loaded | **merges** — new terms append, existing ones absorb the harvested source and evidence |

So to add harvested terms to an existing glossary: **load the glossary first**
(Home → the saved row), *then* Harvest. Do it the other way round and you are
looking at the harvest on its own, with your glossary still safe on disk but not
in the grid.

> **Harvest is not *Add to glossary*.** The button on a Connect row runs the app's
> **own scan** of that source; Harvest reads **PDC's catalog**. On an object store
> they return different things: *Add to glossary* gives one term per file, while
> Harvest — once Data Discovery has profiled those files — gives a term per
> **column inside** them. On the AWC estate that is 5 terms versus 47.

> **Same concept, two categories = two rows.** Rows key on **Category + Term**, so
> a `Turbidity Ntu` already filed under *Water Quality* and a harvested one
> categorised *Water System* will not merge — they append. The duplicate resolver
> on Review flags them, but the real fix is upstream: correct the category mapping
> in the domain pack so both land in the same place.

> **The base URL is the server root.** Give the app `https://host`, not the
> Keycloak realm URL — the app appends `/keycloak/realms/<realm>/…` and
> `/api/public/v{n}/…` itself. A full Keycloak URL is tolerated and stripped back.

# API reference card

| Purpose | Method & path | Body / key fields |
| --- | --- | --- |
| Get token | `POST /api/public/v2/auth` | form: username, password, client_id, grant_type, scope |
| Find term | `POST /api/public/v2/search` | `{ searchTerm, searchFacets:{ type:["term"] } }` |
| Find column | `POST /api/public/v2/entities/filter` | `{ filters:{ fqdns \| names \| parentIds \| types } }` |
| Write column | `PATCH /api/public/v2/entities/{id}` | `{ attributes:{ businessTerms[], features{} } }` |
| PDC profiling | `POST /api/public/v2/entities/filter/profiling-info` | `{ filters:{…} } ?sampleLimit=N` |
| Trust Score job | `POST /api/public/v3/jobs/execute/calculate-trust-score` | `{ scope:[ ids ] }` |
| Profile files | `POST /api/public/v3/jobs/execute/data-discovery` | `{ scope:[ ids ], configs:{ buildSamples, withProfile } }` |
| Poll a job | `GET /api/public/v2/jobs/{id}/status` | → `{ status, activity, duration }` |
| Harvest sources | `POST /api/public/v2/entities/filter` | `{ filters:{ types:["SCHEMA"\|"COLUMN"] } }` |
| Glossary exists? | `POST /api/public/v2/search` | `{ searchTerm }` → a GLOSSARY hit |
| Source by id | `GET /api/public/v3/data-sources/{id}` | (no list-all; retrieve by id) |

# Production notes & caveats

| Topic | Note |
| --- | --- |
| **Token lifetime** | Authenticate once per run and re-auth on a 401 rather than caching across sessions. Never write it to disk. |
| **Least privilege** | Admin works, but the rights actually needed are glossary read, entity edit and job execute. A Business Steward is plenty and safer. |
| **Version drift** | Confirm the path version against your instance Swagger; the jobs catalog is richest in v3. |
| **Dry-run discipline** | Always preview against a new instance. Arrays full-replace on PATCH — the dry-run is what proves the merge produces a superset. |
| **Idempotency** | Re-applying is safe: the app merges by term id/name, so the same link will not duplicate. Jobs can be re-run freely. |
| **Base URL** | The PDC server root, and the **vhost** — not an IP, and not the Keycloak realm URL. |
| **The import boundary** | Nothing here creates a glossary. If the glossary changes, re-import it (whole-glossary, non-incremental) before resolving and applying again. |

> **End of workshop.** You have taken the glossary from a local suggestion to a
> fully governed, trust-scored, profiled set of columns in PDC — every step after
> the import driven by the public API.

---

# Appendix A — The API behind the app (Swagger reference)

The app is a thin client over the PDC public API. Every button maps to one or more
of the calls below, taken from your instance's OpenAPI document (openapi 3.0.3) at
`/api/public/v{1,2,3}/`. Bodies are abbreviated to the fields the app sends or reads.

### A1 · Authenticate — `POST /api/public/v{n}/auth`

Posts form-encoded credentials, reads `data.accessToken`, sends it as
`Authorization: Bearer` on every later call.

```http
POST /api/public/v2/auth
username=<user> password=<pwd> client_id=pdc-client
grant_type=password scope=openid profile email

200 { "message": "OK", "data": { "accessToken": "eyJhbGciOiJIUzI1NiIsInR..." } }
401 { "status": 401, "message": "Unauthorized" }
```

### A2 · Resolve a column or term — `POST /api/public/v{n}/entities/filter`

The workhorse lookup. Apply uses it to resolve a column id; Resolve uses it
(`names` + `types:["term"]`) to read a term's `_id` and `rootId`.

```jsonc
// request ?extended=true&size=500   (size is capped at 500)
{ "filters": { "fqdns": ["cscu_core.members.member_name"], "types": ["COLUMN"] } }
// filters also accept: names, parentIds, rootIds, resourceIds, collectionIds,
// buckets, profileStatus[COMPLETED|SKIPPED|FAILED], profiledAt{min,max}
// (v3 also: tags, terms, termIds)

// 200
{ "status": 200,
  "data": [ { "_id": "5f3a...e21", "name": "member_name", "type": "COLUMN",
      "fqdn": "cscu_core.members.member_name", "parentId": "...", "rootId": "...",
      "attributes": {
        "features": { "sensitivity": "HIGH", "qualityScore": 92,
                      "rating": { "value": 4 }, "isLineageVerified": true,
                      "isCriticalDataElement": true },
        "businessTerms": [ { "id": "...", "glossaryId": "...",
                             "name": "Member Name", "confidenceScore": 1 } ] } } ],
  "cursorInfo": { "cursor": null, "size": 1, "totalItems": 1 } }
```

> The cursor is a **query parameter** in v2/v3, not a body field — sending it in
> the body silently loops page 1 on any catalog over 500 entities.

### A3 · Faceted search — `POST /api/public/v{n}/search/facets`

Free-text search returning faceted **counts** (not entity hits), so to fetch a
term's exact id the app uses A2. The facets power a governance-coverage view.

```jsonc
{ "searchTerm": "member", "searchFacets": { "type": ["term"], "sensitivity": ["HIGH"] } }
// searchFacets keys: index, type, rootIds, businessTerms, fileFormats, sensitivity,
// domain, qualityScore, trustScore, columnKeys, tags, buckets, parentIds,
// profiledAt, modifiedAt, accessedAt
```

### A4 · Write metadata — `PATCH /api/public/v{n}/entities/{id}`

Merge-and-write. Reads the entity (A2), unions `businessTerms`, overlays
`features`, PATCHes the superset — arrays full-replace, so the whole merged list is
sent.

```jsonc
{ "attributes": {
    "businessTerms": [ { "id": "...", "glossaryId": "...", "name": "Member Name" } ],
    "features": { "sensitivity": "HIGH", "isCriticalDataElement": true,
                  "isLineageVerified": true, "rating": { "value": 4 },
                  "qualityScore": 92 } } }
// valid businessTerms keys: id, glossaryId, name, sourceName, sourceType,
// confidenceScore  (anything else -> 400)
```

### A5 · Trust Score job — `POST /api/public/v{n}/jobs/execute/calculate-trust-score`

```jsonc
{ "scope": [ "<entity id>", "<entity id>" ] }
// 200 { "status": "OK", "data": { "_id": "<job id>", "workerName": "...", "activity": "..." } }
```

### A6 · Data Discovery job — `POST /api/public/v{n}/jobs/execute/data-discovery`

```jsonc
{ "scope": [ "<folder / file id>" ],
  "configs": {
    "computeChecksum": true,     // duplicate detection
    "ingestProperties": true,    // PDF / Office properties
    "buildSamples": true,        // extract samples -> profiling
    "headerExists": true,        // first row is the header
    "contentScanType": "SCAN_ONLY",
    "withProfile": true } }      // v3 only: profile object stores
// more configs: summarizeDocuments, addressDetection, businessTerms, dictionaryIds,
// dataPatternIds, extensions, supportedMaxFileSize, includePatterns,
// excludePatterns, dataProfiledSinceDays ...
```

### A7 · Poll a job — `GET /api/public/v{n}/jobs/{id}/status`

```jsonc
{ "workerId": "...", "workerName": "...", "activity": "...",
  "status": "COMPLETED", "duration": 12.4,
  "scope": { "dataSources": [...], "scope": [...] } }
```

> **Read your own Swagger.** Every shape above comes from a live OpenAPI document.
> Open `/api/public/v3/` for the Swagger UI, or fetch its JSON to script against
> the exact version your box runs. The Glossary Generator publishes its **own**
> API docs at `/docs`.

---

# Appendix B — Drift, Reconcile & the Registry

The Registry unifies the three things a steward used to set by hand in separate
places: the business term, the governed tags, and the sensitivity level. One
canonical entry per concept carries all three, and both the glossary term and the
Data Identification method are generated from that same entry — so the glossary tag
and the method tag **cannot drift apart by construction**.

## Deterministic sensitivity

Sensitivity is decided rules-first against a codified taxonomy, not guessed by a
model. A person identifier — a member or customer id — is HIGH and tagged PII,
while a bare surrogate or foreign key is LOW. The sensitivity is an **ordinal
floor**: rules can raise a classification, and the model never lowers a rule hit.
Tags are drawn from a controlled allow-list derived from the Registry.

> **The model never sets a governed field.** The AI pass is explicitly told not to
> return sensitivity or PII, and the scan classifier is re-asserted deterministically
> after every run — so a bad value from an import, a legacy scan or any agent cannot
> survive. An `ssn` mislabelled `PERSONAL_NAME` becomes `GOVERNMENT_ID`; a spurious
> `ADDRESS_INFO` on an id column is cleared.

## Why drift is visible only after reconciliation

A dictionary method can only be matched back to a concept by its
`dictionaryTermId` — and that id does not exist until the reviewed glossary has
been imported into PDC, which mints the ids, and those ids have been read back and
reconciled into the Registry. The loop is:

```text
scan & classify -> review (merge / disambiguate / keep) -> export glossary
  -> import into PDC (PDC mints term ids) -> reconcile ids into the Registry
  -> emit & deploy methods -> drift check
```

Until reconcile writes the minted ids, dictionary methods have no id to match and
read as **UNKNOWN**. Pattern methods bind by category name, so pattern drift can be
observed a step earlier — but the complete picture still follows reconciliation.

The drift linter reads a deployed method back and reports **OK / DRIFT / UNLINKED /
ORPHAN** per method; reconcile rolls a catalog scan and the deployed methods into
per-concept verdicts of **CLASSIFIED / UNKNOWN / MISSING / DRIFT / UNLINKED**.

## A persistent Registry

The Registry is persistent state, saved alongside the glossary
(`registries/registry.<glossary>.json`) and reloaded on open. This matters because
the reconcile handshake is **stateful**: a dictionary method binds to a concept by
its glossary term id, so if those minted ids were lost on restart, drift could no
longer be assessed next session. The saved Registry is a governance artifact tied
to that glossary *and* that PDC instance.

## Descriptions: prose from the model, links from a verified map

Description enrichment deliberately separates two jobs, because a small local model
will hallucinate regulation names, section numbers and — most dangerously — live
URLs, and a governance term citing an invented regulation is worse than one citing
nothing. The model is asked only to write one or two plain sentences describing the
concept, and is explicitly instructed **not** to produce citations or links. The
links come only from a curated, human-verified reference map carried in the domain
pack, keyed by concept or tag, each stamped with the date it was verified. This is
the same principle as the controlled tag allow-list: **the model proposes within a
controlled vocabulary and never mints authoritative facts.**

## Build the policy from the Term, and pick up its tags

Should the Policy Generator build methods from the Term (carrying that term's
governed tags), or from the tags? With this Registry they are the same outcome —
for a reason worth stating. The **Term is the canonical anchor**: it has an
identity, links to the glossary, and carries a fixed governed tag set. Tags are
attributes of that term. So authoring term-first — one method per concept, emitting
that concept's tags — guarantees consistency. A tag-first approach yields the same
methods only because the Registry already binds tags to terms, and it has no stable
anchor to resolve or merge against.

**So: build from the Term, match the tags.** Tag consistency is not a competing
goal — it is a consequence of term-anchored authoring against one governed
vocabulary.

## Where these live in the app

| Page | What it holds |
| --- | --- |
| **Connect** | Connections, the bulk loader, saved-connection export, Get token, Harvest from PDC |
| **Schema** / **Files** | The ER diagram with PK/FK badges; the object-store browser |
| **Review** | Prune, the AI pass, per-row AI review, duplicate resolution |
| **Dictionary** | Govern the company vocabulary: terms, tags, rules, pending approvals, sensitivity floors, facet preview, audit trail, export |
| **Govern** | Stewardship, roster, Generate JSONL, Draft policies, the Registry hand-off card |
| **Apply** | PDC connection, Data Elements, Resolve term IDs, Apply to PDC, Profile documents |
| **Settings** | LLM provider and model, hardware, lab object store, backups, appearance |
