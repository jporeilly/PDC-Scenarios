# Workshop — Data Identification with the Policy Generator

*Copper State Credit Union (CSCU) scenario · app 1.8.x · validated against PDC 11.0.0*

**Primary role:** Data Steward / Data Developer
**Estimated time:** 75–100 min
**Prerequisites:** the Glossary Generator workshop completed on CSCU — the
glossary reviewed and imported into PDC, and the app's Generate step has
written the **Classification Registry**
(`glossary_generator/registries/registry.<glossary-uuid>.json`). Both apps
installed on the host (the `C:\PDC-Demo` bootstrap does this and builds the
Policy Generator's React UI for you). Python 3.9+. PDC reachable over HTTPS
as `catalog.admin` — the account allowed to import under
**Management → Data Identification** and to run jobs.

---

## 1. The scenario

**Copper State Credit Union**'s governed glossary now exists in PDC — but the
catalog still has to *recognize* CSCU's data on its own. New tables arrive,
documents land in the bucket, and every scan asks the same question: which
columns hold member numbers, routing numbers, risk ratings, SAR statuses?

Data Identification answers it with **methods** — Data Patterns and
Dictionaries that classify, tag and bind columns to business terms. Workshop 5
and Technical Track Module 03 taught you to author them **by hand**. This
workshop authors the same methods **from evidence**: the Registry the Glossary
Generator exported carries, for every governed concept, the **detection
seeds** its scan induced from profiled data — value-format regexes like
`^CSCU-\d{6}$` and reference-value lists (risk ratings, SAR statuses, account
types). The Policy Generator turns those seeds into import-ready methods that
stamp **only governed tags** and bind **only governed terms**.

Because both apps read the same Registry row, the term a method binds, the
tags it stamps, and the sensitivity can never quietly diverge — that is the
contract. And this time you run the **whole lifecycle in the app's web UI**:
**Load → Author → Reconcile → Deploy → Drift-check** — five pages, one
stepper, ending with the proof that what PDC identifies still matches what
the glossary governs. (The same engine also runs headless — the CLI is the
appendix.)

## 2. What you will build

An import-ready **Data Identification method set** for CSCU — one
DataPattern envelope per regex seed, one Dictionary envelope (definition
JSON + values CSV) per reference-list seed — the exact format PDC's own
Export produces — each assigning the Registry's governed tags (`pci`, `aml`,
`lending`, … always lower-case) and binding its governed business term.
Authored in the UI, **reconciled** against the live glossary's minted term
ids, **deployed** into PDC over PDC's own import API, exercised by a Data
Identification run — and finally **drift-checked**: every deployed method
compared against the Registry, verdict by verdict, including one drift you
manufacture on purpose and repair.

## 3. Lab flow

### Step 1 — Launch the app

```powershell
cd C:\PDC-Demo\policy_generator
.\run.ps1                      # → http://127.0.0.1:5001
```

(The Glossary Generator keeps port 5000 — both apps run side by side. On the
lab VM it's `bash run.sh --host 0.0.0.0` → `http://192.168.1.200:5001`.)

Open `http://127.0.0.1:5001` and take the thirty-second tour before clicking
anything:

- The **sidebar** is the canonical PDC-suite shell: a **WORKFLOW** section
  with the five stages — **Load**, **Author**, **Reconcile**, **Deploy**,
  **Drift** — and a **CONFIGURE** section holding **Settings** (theme, build
  info). The version chip under the app name opens the changelog.
- The **stepper** across the top of the content mirrors the sidebar and is
  **gated**: Author and Reconcile unlock the moment a Registry loads; Deploy
  additionally needs a live PDC session *and* at least one reconciled term
  id; Drift needs a Registry plus the PDC session. Locked steps are grayed —
  the gates are the workflow.
- The **sidebar footer** shows the live PDC session: right now the dot is
  amber — **PDC · not connected**. Watch it in Step 4.
- Every page opens with a collapsed **explainer card** ("Under the hood…") —
  the Registry contract on Load, the skipped-groups legend on Author, what
  Deploy actually does, how to read the Drift verdicts. Expand them as you
  reach each page; they are the workshop's margin notes, built in.

[SCREENSHOT: the Policy Generator freshly loaded — sidebar (WORKFLOW / CONFIGURE), gated stepper, amber PDC dot in the footer]

### Step 2 — Load the CSCU Registry

The Glossary Generator wrote the Registry at Generate time, one file per
glossary, regenerated on every export. You don't go looking for it — the
**Load** page's *Discovered in the co-located Glossary checkout* table
already lists it, because the app probes for Registries on startup:

- the **parent folder** of its own checkout, for
  `glossary_generator/registries/registry.*.json` — which is exactly the
  `C:\PDC-Demo` (and lab-VM `~/PDC-Demo`) layout, where `policy_generator/`
  sits beside `glossary_generator/`;
- **sibling Glossary checkouts** next to the app;
- or wherever **`POLICY_REGISTRY_DIR`** points, if you set it.

Matches are listed newest-first with the glossary name and concept count; a
single match loads itself, otherwise click the CSCU row. If the two apps run
on different hosts the paths won't resolve — use **⬆ Upload registry.json**
instead (drag-drop works).

If you re-reviewed the glossary since the last export, re-**Generate** in the
Glossary app first — export time is the latest reviewed state.

The **summary card** appears and the stepper's Author and Reconcile steps
unlock. Read the five tiles like a steward — this is the contract summary,
and the page's *"Under the hood — the Registry contract"* explainer (with the
two-app handoff graphic) tells you what each number means:

- **concepts** — one per governed term the glossary exports.
- **seeded (authorable)** — how many carry detection seeds. Only these can
  become methods; the rest are governed by other mechanisms (Step 3).
- **term ids resolved / unresolved ids** — **unresolved > 0** means the
  Glossary app's **Resolve term ids** step hasn't been run since import (or
  the Registry wasn't re-exported after it). Authoring still works — rules
  bind the business term **by name** until ids are resolved — and Step 4's
  Reconcile fixes it from this side.
- **governed tags** — the embedded allow-list. Off-vocabulary anything is
  drift out of the Glossary app — fix it there; the author stage refuses
  off-vocabulary tags rather than letting them into PDC.

[SCREENSHOT: Load page — the discovered CSCU Registry row and the five summary tiles]

### Step 3 — Author the method set

Open **Author**. The page previews the whole method set before you download
anything. Type **`CSCU`** in the *Name prefix* field and click **↻ Preview**
(the prefix defaults to the glossary name — set it explicitly so your methods
group together in PDC and every later stage scopes to it).

Two tables appear — **Data Patterns** and **Dictionaries** — one row per
method the seeds justify. Review them like a steward; every column is one
the CSCU Technical Track taught:

- **Method** — prefixed (`CSCU …`), so the set groups together in PDC.
- **Term / Bound** — the governed term the Glossary app owns, with a badge:
  **✓ by id** once the Registry carries the minted term id, **⚠ by name**
  until then (Reconcile turns these green).
- **Content regex / Signature** — the induced value regex (e.g.
  `^CSCU-\d{6}$` for member numbers) and its position signature. Both came
  from profiled sample values — nothing here was hand-typed.
- **Column hint** — a regex derived from the Registry's physical `sources[]`
  (the real columns the term maps to), not guessed from the term.
- **Tags** — governed, lower-case, re-filtered against the Registry's
  embedded allow-list at authoring time.

For dictionaries, the **Values** count and **Sample** column show the
reference values profiling actually saw (risk ratings, SAR statuses, account
types) — confirm they read like CSCU's codes, not noise.

### Why most concepts have no method — the three mechanisms

Below the tables, the **Skipped concepts** section lists everything that got
no method — grouped by governance mechanism, with the *"What these groups
mean"* explainer card above the groups. Expect the skipped list to be **most
of the glossary**, and expect that to be correct: identification methods are
only one of three mechanisms that apply and check governed terms.

| Mechanism | What it covers | Where it happens |
| --- | --- | --- |
| **Apply** (mapping-based binding) | *every* reviewed term: the Glossary app PATCHes the term link, governed tags and sensitivity directly onto the mapped columns (the Registry's `sources[]`) | Glossary app → Apply to PDC |
| **Identification methods** (value-based recognition) | only concepts with a stable value shape — an induced format or a reference list. Their job is *new and unknown* data: a new table, a file in the bucket, a rogue column | this app's authored set — custom methods only |
| **Business rules** (semantic checks) | what no shape can express: opt-out honoured, CVV must be absent, SSNs must not appear in `note_txt` | Workshop 04 rules + Trust Score |

Reading the four groups on the page:

- **⚠ Needs a detection seed** — identifiable data (SSN, email, phone, ZIP)
  and reference lists whose scan produced no seed. The only amber group —
  the only one that wants action, and the action is **glossary-side**:
  re-scan with profiling, or add a `curated_seeds` entry to the domain pack,
  then re-export the Registry. Seeded, they become fully auditable custom
  methods (the custom-only program's replacement for PDC's built-ins).
- **· Structural — correctly method-less** — record/report/summary concepts
  describe containers, not values; no method *should* exist. Apply governs
  the whole table or document folder.
- **ℹ Free text — needs a vocabulary rule** — notes and description fields
  have no stable shape; forcing a regex here is the free-text blind spot
  Workshop 05 warns about. Vocabulary dictionaries or business rules govern
  them.
- **· Govern by mapping** — amounts, dates, ids, statuses, names: no stable
  shape, and none needed — Apply already governs them on their mapped
  columns.

The loop is closed in Step 8: the **drift-check** compares deployed methods
against the Registry's governed vocabulary, so anything that stops matching
what the glossary governs is flagged instead of drifting silently.

[SCREENSHOT: Author page — pattern and dictionary preview tables, and the skipped concepts grouped by mechanism]

### Download the bundle — the reviewable artifact

Click **⬇ Download import zip**. One zip holds the whole set, in the exact
layout PDC's own **Export** produces — that is the import contract, and it's
why the app emits it byte-compatible:

```text
patterns-import.zip        one cscu_<term>.json per pattern (flat) — the
                           exact layout PDC's own Pattern Export produces
dictionaries-import.zip    one nested cscu_<term>.zip per dictionary,
                           pairing the definition JSON with its Term-header
                           values CSV — PDC's Dictionary Export layout
INDEX.csv                  kind, rule name, file, term, term_id
README.txt                 import pointers
```

Open one pattern JSON and one dictionary before moving on: **name**
(prefixed), the **column-name hint**, **regexMatch / profilePatterns**, the
governed **applyTags**, and **applyBusinessTerms** `[{name, id}]` — the live
PDC 11 term-binding field, verified round-trip. `INDEX.csv` is your review
manifest: one row per method with its term and (when resolved) term id.

> **Checkpoint discipline:** the zip is the thing you can put in front of an
> auditor *before* anything touches PDC. Deploy (Step 5) uploads these exact
> bytes — review now, not after.

[SCREENSHOT: a CSCU pattern rule JSON beside its INDEX.csv row]

### Step 4 — Reconcile: connect to PDC and bind the term ids

Open **Reconcile**. Two things happen on this page: the app gets its **live
PDC session** (which Deploy and Drift both gate on), and every concept's
term binding gets verified against the glossary PDC actually holds.

**Connect to PDC** with the lab values:

| Field | Value |
| --- | --- |
| Base URL | `https://pentaho.io` |
| Username | `catalog.admin` |
| Password | `copperstate` |
| Verify TLS certificate | leave **unchecked** — the lab VM's certificate is self-signed |

Click **Connect**. The card shows **✓ catalog.admin @ https://pentaho.io**
— and the sidebar footer's dot turns **green**: *PDC · catalog.admin*. The
session lives across pages (that's what unlocks Deploy and Drift in the
stepper); the token is held in memory only, the password never stored.

Now click **⇄ Run reconcile**. The app looks every concept's term up in PDC
(the Glossary app's proven three-path lookup) and streams a verdict per term:

- **✓ verified** — PDC's id matches the Registry's. Nothing to do.
- **ℹ resolved** — found in PDC; the Registry had no id yet. The normal case
  when you skipped Resolve glossary-side.
- **⚠ mismatch** — PDC's id differs from the Registry's (a re-imported
  glossary mints new ids). Rebind.
- **✋ missing** — the term isn't in PDC at all: the glossary wasn't imported,
  or the term never left review. Fix glossary-side first.

Click **Apply N id(s) to Registry** — the found ids are stamped into the
loaded Registry, the Author preview's **⚠ by name** badges flip to
**✓ by id**, and the **Deploy** step unlocks. **⬇ Export reconciled
registry** keeps a copy of the id-solid Registry beside your bundle.

[SCREENSHOT: Reconcile page — verified/resolved counts after the run, ids applied, and the footer dot green]

### Step 5 — Deploy: dry-run first, then live

Open **Deploy** — new territory: in the earlier revision of this workshop
you carried the zip to PDC by hand. Deploy does the same import
**programmatically over PDC's own worker API** — the multipart
`POST /api/importWorkerFiles` upload that PDC 11's UI zip-import itself uses
— then does two things the manual path can't: it **verifies every method
landed**, and it **re-stamps the reconciled term ids** into each method's
term binding (PDC's importer rewrites ids it cannot resolve; the re-stamp
puts the minted ids back). The page's *"Under the hood — what Deploy does"*
explainer walks the exact sequence.

Confirm the *Name prefix* reads **`CSCU`**, then — **always** — click
**Preview (dry-run)** first. The dry-run returns the plan without touching
PDC: a **+ create** / **↻ update** count and a per-method row for each
pattern and dictionary. On a first deploy everything is *create*; on any
later one it's *update* — every method carries a deterministic `_id`, so a
re-deploy is an **upsert** that overwrites the same method in place, never a
duplicate.

> **Checkpoint:** the dry-run's create + update total equals the Author
> preview's pattern + dictionary count. If it doesn't, your prefix differs
> between the two pages.

[SCREENSHOT: Deploy dry-run — the create/update plan for the CSCU set]

Now click **🚀 Deploy** and confirm. Watch the sequence report itself:

1. **Worker badges** — `patterns import: COMPLETED`,
   `dictionaries import: COMPLETED`. The zips upload, and the import workers
   are polled to completion.
2. **Counts** — **✓ imported** should equal the full method count;
   **⚭ id-bound** counts the methods whose term binding was re-stamped with
   the Registry's minted id.
3. **Per-method rows** — each method shows **✓ imported + bound** (or
   **⚠ by name** for any concept still without an id — deploy them anyway;
   a later Reconcile + re-deploy upgrades the binding).

Everything imported carries the `CSCU` prefix — that's the **prefix guard**:
Deploy can only touch the set it authored, and the Reconcile page's scoped
**🗑 Retire set…** can always delete exactly that set and nothing else
(built-ins refused — useful because PDC 11's own method list has **no
Delete**, its ⋮ menu offers only View and Edit).

[SCREENSHOT: Deploy results — workers COMPLETED, imported/id-bound counts, per-method ✓ imported + bound rows]

Verify in PDC: **Management → Data Identification** now lists the
`CSCU`-prefixed methods under Patterns and Dictionaries, grouped by prefix
alongside the built-ins.

> **The manual path — still valid, now the alternative.** The zip you
> downloaded in Step 3 imports by hand in PDC under **Management → Data
> Identification**: **Patterns → Import** (upload `patterns-import.zip`
> whole) and **Dictionaries → Import** (upload `dictionaries-import.zip`
> whole; each nested zip pairs a definition JSON with its values CSV — they
> must travel together). Same bytes, same result, minus the automatic
> verify and term-id re-stamp — after a manual import, run Reconcile so the
> bindings are id-solid.
>
> [SCREENSHOT: PDC Data Identification import dialog with the CSCU method set]

> **Caveat (both paths):** PDC's *edit* form does not display an imported
> rule's condition, even though View → Rules shows it and it evaluates.
> Don't hand-edit imported methods — a save could persist the emptied
> condition. The governed change path is: adjust in the Policy Generator (or
> the Registry/pack) and **re-deploy** — deterministic ids make re-deploys
> clean upserts. Step 8 shows you exactly what happens when someone ignores
> this.

### Step 6 — Run Data Identification

Run **Data Identification** in PDC on the CSCU sources
(`CopperState_Core_Banking`, then **Scan Files** on
`CopperState_Documents`) so the new methods execute — same as Workshop 5.

> **Best practice:** at **Select Methods**, run identification on your
> custom set only — leave the built-ins unselected. Every tag stamped in a
> governed run should trace to a versioned, evidence-based method; the
> built-ins are opaque and release-dependent, so they stay demo-only.

(The Deploy page's optional **Run identification** card can queue the same
`DATA_IDENTIFICATION` job from the app — scoped to your deployed set and to
explicit entity ids you paste from PDC's catalog, never catalog-wide. Use
whichever side you prefer; the PDC-side run is the one the earlier workshops
taught.)

[SCREENSHOT: Data Identification job completed on CopperState_Core_Banking]

### Step 7 — Verify the governed vocabulary landed

- Search/filter by tag: the governed facets (`pci`, `aml`, `member`, …) now
  match columns your methods classified — and **only** governed tags appear;
  the method set cannot introduce a stray facet.
- Open `cscu_core.members.mbr_no`: the member-number pattern matched, the
  column carries the term *Member Number* and its tags.
- Check a dictionary hit: `suspicious_activity.risk_rating_cd` classified from
  the risk-rating reference values.

[SCREENSHOT: a column tagged by a CSCU method, showing term + governed tags]

### Step 8 — Drift-check: prove it, break it, prove it again

Open **Drift** — the page that closes the loop, and the one Nadia Flores
(CSCU's BSA/AML officer) would sign an audit off on. It reads every deployed
method under the prefix, in full, and compares it against the Registry's
governed facts: tags vs the allow-list, the term binding (name **and** id),
the content regex and profile signature vs the seeds, dictionary row counts
(PDC doesn't expose dictionary values over its API, so the count is the
honest proxy), and the enabled state. One verdict per method — the page's
*"Under the hood — reading the verdicts"* explainer in brief:

- **✓ clean** — every governed fact matches the Registry.
- **⚠ drifted** — deployed, but a governed fact diverged; the findings
  column names exactly what.
- **ℹ orphaned** — carries the prefix but the Registry no longer authors it:
  the concept was retired or renamed glossary-side. A candidate for the
  scoped Retire.
- **✋ missing** — the Registry authors it but PDC doesn't have it: never
  deployed, or deleted in PDC. Re-deploy restores it.

With the prefix at **`CSCU`**, click **⚖ Run drift-check**. Fresh off
Step 5, every method should read **✓ clean** with its checks-passed count —
screenshot that; it's the baseline.

[SCREENSHOT: Drift-check — every CSCU method ✓ clean]

#### Exercise — manufacture a drift, catch it, repair it

Someone will eventually "just fix" a method in PDC directly. Be that someone,
once, deliberately:

1. In PDC, open **Management → Data Identification → Dictionaries**, find
   **CSCU Risk Rating Code**, and **Edit** it: change its `aml` tag to `AML`
   (or add an off-vocabulary tag like `internal`). Save.
2. Back in the app, **⚖ Run drift-check** again. The method flips to
   **⚠ drifted**, and the findings name the exact fact: an off-vocabulary
   tag that isn't on the Registry's allow-list — precisely the `PII` vs
   `pii` fragmentation the contract exists to prevent. (Your hand-edit may
   also have emptied the rule's condition — the Step 5 caveat in action —
   and drift-check flags that divergence too.)
3. **The fix flows one way.** Never hand-edit the deployed method back —
   correct glossary-side if the governed fact was wrong, or **re-deploy** if
   PDC diverged. Here PDC diverged: return to **Deploy** and deploy again —
   the upsert overwrites the edited method with the governed one. (Had the
   verdict been **ℹ orphaned** — a term that left the glossary — the answer
   would be the Reconcile page's scoped **Retire** instead.)
4. Run the drift-check one last time: **✓ clean** across the board.

[SCREENSHOT: Drift-check after the hand-edit — the risk-rating dictionary ⚠ drifted with the off-vocabulary finding]

That round-trip — clean, drifted, clean — is the operational habit this app
exists for: the drift-check is not a one-time step but the periodic audit
that keeps Data Identification honest against the glossary.

## 4. Checkpoints

| # | Check | Evidence |
| --- | --- | --- |
| 1 | Registry loaded clean | Load tiles: seeded > 0; governed tags counted; unresolved noted |
| 2 | Method set authored | Author preview: patterns + dictionaries under the `CSCU` prefix |
| 3 | Bundle reviewed | zip in hand: `INDEX.csv` row per method; a pattern's `applyTags` ⊆ the allow-list (spot-check) |
| 4 | PDC session live | footer dot green — `catalog.admin` @ `pentaho.io` |
| 5 | Term ids bound | reconcile ran; ids applied; Author badges read ✓ by id; reconciled registry exported |
| 6 | Deploy plan sane | dry-run create + update = the authored method count |
| 7 | Set deployed | both workers COMPLETED; ✓ imported = method count; ⚭ id-bound |
| 8 | Identification ran | job completed on both CSCU sources |
| 9 | Vocabulary landed | governed tag facets match; `mbr_no` carries *Member Number* |
| 10 | Drift proven & repaired | baseline clean → hand-edit flagged ⚠ drifted → re-deploy → clean |

## 5. Where the story continues

The lifecycle is complete: the same Registry row now governs what the
glossary *says* (Apply), what the catalog *recognizes* (your deployed
methods), and what an audit can *prove* (the drift-check). What remains is
operations — re-Generate and re-deploy when the glossary evolves, drift-check
on a schedule, Retire when a term leaves the vocabulary — and the semantic
layer no shape can express: the Workshop 04 business rules (opt-out honoured,
CVV absent, no SSNs in free text) and the Trust Score that rolls it all up.

## Appendix — the CLI: same engine, zero dependencies

Everything the Load and Author pages do also runs headless — same engine,
stdlib-only, no venv, no browser — for scripted or CI use:

```sh
python -m policy_generator info path/to/registry.<uuid>.json
```

`info` prints the contract summary the Load page renders as tiles: the
glossary name and id, concept count, how many concepts carry detection seeds,
how many have **resolved term ids**, and the governed-tag count. (When the
repo is cloned into the same folder as `glossary_generator/` — the `PDC-Demo`
layout the installer produces — omit the path: the newest Registry is
auto-discovered, exactly as on the Load page.)

```sh
python -m policy_generator author path/to/registry.<uuid>.json -o out/ --prefix CSCU
```

`author` writes the same bundle the **⬇ Download import zip** button
produces:

```text
out/
  patterns-import.zip        one cscu_<term>.json per pattern (flat)
  dictionaries-import.zip    one nested cscu_<term>.zip per dictionary
                             (definition JSON + Term-header values CSV)
  INDEX.csv                  kind, rule name, file, term, term_id
  README.txt                 import pointers
```

Concepts without seeds are listed as **skipped**, with the reason — the same
groups the Author page color-codes. `--zip out/cscu-methods.zip` writes the
set as one zip if you prefer a single artifact.

The connected stages — Reconcile, Deploy, Drift-check — need the live PDC
session and run over the web UI (or its API: the interactive docs at
`http://127.0.0.1:5001/docs` expose every endpoint, typed and try-able).

---

*All Copper State Credit Union data — members, accounts, transactions, SARs
and documents — is fictional and generated for training.*
