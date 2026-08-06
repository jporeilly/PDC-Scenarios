# Changelog

## [1.4.0] — 2026-08-05

### Added — `load-pdc-users.ps1`: load the cast into Keycloak from Windows

- The bash loader runs **on the lab VM** and drives `kcadm.sh` inside the
  `pdc-um-keycloak-1` container, which a Windows host cannot reach. The
  PowerShell counterpart talks to Keycloak's **Admin REST API over HTTPS**
  instead — no Docker, no SSH, no shell on the VM.
- Same roster, same role matching, same options: `-Scenario`, `ALL`, `-DryRun`,
  `-Password`, `-FixPolicy`, `-ListRoles`, plus `-SkipTlsCheck` for the lab's
  self-signed certificate. Idempotent — an existing user is kept and has its
  password and roles re-applied.
- **Six named checkpoints** so a failed run says *where* it stopped and what that
  stage proves: connect → roster → password policy → realm roles → load → verify.
  Only checkpoint 5 writes anything; the first four are read-only, which means a
  bad base URL or credential is caught before a single user is touched.
- Each checkpoint carries the hint for its usual failure, because these are
  environmental rather than code: use the **vhost not an IP** (PDC's proxy routes
  by hostname), `-SkipTlsCheck` for a self-signed cert, and `-FixPolicy` when a
  realm policy such as `specialChars(1)` rejects the simple training passwords.

### Added — make targets
- `make users ID=CSCU` — dispatches to the **shell** runner when a Keycloak
  container is present (you are on the VM) and otherwise prints the exact
  PowerShell command, rather than failing obscurely on a missing Docker.
- `make users-check ID=CSCU` — dry run, changes nothing.
- `make users-roles` — the realm's **actual** roles and groups. Roster names are
  matched against these, never assumed; unmatched names are reported loudly so
  the alias table can be extended.

## [1.3.6] — 2026-08-05

### Added — module 01 teaches what counts as evidence that two terms are one concept

- New section and three slides on the similarity advisor's evidence ranking: FK
  link, coded value-set overlap, distinctive format identity, PII mismatch —
  strongest first, with **why each is sound**.
- **The teaching point: a property of the data TYPE is not identity of the
  CONCEPT.** `^0\.\d{2}$` means *"a small decimal"*, which `lead_ppb`,
  `copper_ppm` and `turbidity_ntu` all match; scoring that as *same concept*
  ranked `Lead Ppb ← Turbidity Ntu` at **0.85 strong**, and merging it would put
  one regulated contaminant's limits on another's term. Value overlap fails the
  same way on numbers: `Paid Bills` and `Outstanding Bills` both draw from
  `{0, 1}` and are opposites.
- Gated in Glossary Generator **1.23.0/1.24.0** — a format counts only when
  distinctive (minted literal text, not digit classes), overlap only for a coded
  vocabulary. Otherwise: no verdict, *"too generic to identify a concept"*.
- **Read the ranking, not the scores.** The tell that scoring measures the wrong
  thing is a *correct* answer ranking below wrong ones — here the one right merge
  scored 0.84 review, below three false positives at 0.85 strong.
- **Find similar is not the duplicate resolver**: the resolver groups identical
  names, Find similar spans different ones, and merging there *renames* a term,
  which then forms a same-name group for the resolver to fold. Two steps by design.
- App-version stamp **1.24.0**; docx 16 tables, deck 36 slides.

## [1.3.5] — 2026-08-05

### Changed — module 01 documents the harvest merge semantics

- New Lab section **"Harvest replaces an empty grid and merges into a loaded
  one"**. The order decides the outcome and nothing said so: harvest with no
  glossary open starts a fresh *unnamed* workspace (which is why it cannot
  damage a saved glossary — nothing autosaves until you name it), while harvest
  with a glossary loaded merges into it. To add harvested terms to an existing
  glossary you must **load the glossary first, then harvest**.
- **Harvest is not *Add to glossary*.** The Connect-row button runs the app's own
  scan of a source; Harvest reads PDC's catalog. On an object store they return
  different things — one term per file versus a term per **column inside** them
  once Data Discovery has profiled the files. On the AWC estate: 5 versus 47.
- **Same concept, two categories = two rows.** Rows key on Category + Term, so a
  `Turbidity Ntu` already in *Water Quality* and a harvested one categorised
  *Water System* append rather than merge. The duplicate resolver flags them; the
  real fix is the category mapping in the domain pack.
- App-version stamp moved to **1.21.0**; the `.docx` regenerated (15 tables).

## [1.3.4] — 2026-08-05

### Changed — module 01 teaches the Data Discovery folder cascade

- Lab F gained two sections, both from a live run that got this wrong:
  **"Scope a folder, not a file"** and **"Reading the result — SKIPPED is not
  always a failure"**. The deck gained the matching pair (33 slides).
- **The cascade.** `scope` takes any entity id, but a FOLDER cascades to every
  file inside it while a FILE profiles only itself — and a Data-Elements payload
  carries *one representative file per folder*. Scope the files and you profile
  5 documents out of 16, and the job still returns SUCCESS. The run message now
  tells you which happened: `awc-documents/compliance` (slashed) is folder
  scope; a dotted `bucket.folder.file` label is the fallback.
- **The gotcha behind it.** PDC types object-store folders **`FOLDER`**, not
  `DIRECTORY` — a live scan reports *"16 FILE + 5 FOLDER entities discovered"*.
  A filter omitting `FOLDER` gets no folder hits at all, because PDC filters
  them out server-side, and the miss is indistinguishable from an uncatalogued
  folder. Fixed in Glossary Generator 1.17.1; anyone writing their own client
  needs both type names.
- **SKIPPED is not always a failure.** csv/tsv/json/jsonl/txt profile to
  COMPLETED with column statistics; pdf/docx get properties and a checksum but
  stay SKIPPED permanently, because there are no rows or columns to sample.
  Neither PDC nor the app can ever score a PDF — so a PDF is the worst possible
  file to verify a Discovery run against. Verify on a file that was *not* the
  representative instead.
- App-version stamp moved to **1.17.1**.

## [1.3.3] — 2026-08-05

### Added — module 01 finally has a markdown source

- `courseware/CSCU/Platform/Technical-Track/01-Glossary-Generator-App/Workshop-Glossary-Generator.md`
  is now the source of truth for the technical workshop, matching the pattern
  modules 02–04 already used. `Workshop-Glossary-Generator.docx` and
  `Glossary-Generator.pptx` (31 slides) are generated from it.
- **Why this mattered.** Module 01 shipped only binaries, stamped `1_6_19` — app
  version 1.6.19. They had drifted ten minor releases: still teaching **Docker**
  (dropped in 1.9.0), the pre-FastAPI layout, and the four-agent toolbar retired
  in 1.15.0/1.16.0. With no text source, every correction meant rewriting a
  binary by hand, which is why nobody did.

### Changed — the content is current to Glossary Generator 1.17.0

- Native launchers (`run.sh` / `run.ps1` / `run.bat`) replace the container
  instructions; API docs at `/docs`; the vhost-not-IP warning for PDC's proxy.
- The **AI pass** replaces the Enrich / AI suggest / AI categorize / AI QA
  roster, with **AI review** for a single row, and the definition linter
  described where it lives — inside the pass, its flags becoming rewrite orders.
- New material the old deck never covered: structural-key auto-pruning and the
  Registry's physical model, the duplicate-resolution escalation ladder
  (evidence → live probe → adjudicator), hosted LLM providers, object-store
  file-scan-before-discovery, and the `Quality/` DQ-expectation rules.
- **Same-named terms must be disambiguated, not kept separate** — Resolve
  matches by name and takes the first hit, so a collision silently mis-links one
  group's columns. Taught explicitly now.
- **Scenario correctness:** water-utility examples had leaked into what is a
  credit-union scenario (`sewer|wastewater|effluent` tag rules, the Arizona ADEQ
  reference set). Replaced with CSCU material — member ids, NACHA return codes,
  BSA/AML vocabulary.

### Removed

- `Workshop-Glossary-Generator-1_6_19.docx` and `Glossary-Generator-1_6_19.pptx`.
  Superseded, and recoverable from git history.

## [1.3.2] — 2026-08-05

### Changed — CSCU Glossary courseware follows the app's agent consolidation

- The Glossary Generator shipped **1.15.0** (Enrich / AI suggest / AI categorize
  / the AI QA judge folded into one batched **AI pass**) and **1.16.0** (the two
  leftover buttons removed; an expanded row gained **AI review**, the same pass
  scoped to one row). The CSCU courseware still taught the old roster, so the
  agent tables, the model-comparison exercise, the tag-refresh steps and the
  Technical-Track module 01 blurb are updated to match.
- The definition linter is now described where it actually lives: inside the
  pass, running *before* the model so its flags become rewrite orders, and
  re-running afterwards so a surviving QA chip means the model could not improve
  the definition from the available evidence.
- Files: `courseware/CSCU/Glossary/Glossary-Generator-LLM-and-Review.md`,
  `Glossary-Generator-Tags-and-Domain-Pack.md`,
  `Workshop-Glossary-Generator-CSCU.md`, and
  `courseware/CSCU/Platform/Technical-Track/01-Glossary-Generator-App/README.md`.

### Known stale — module 01's binary deliverables
- `Glossary-Generator-1_6_19.pptx` and `Workshop-Glossary-Generator-1_6_19.docx`
  are still pinned to app **1.6.19**: they teach **Docker** (removed from the app
  in 1.9.0) and the pre-consolidation agent roster. Module 01 is also the only
  module with no markdown source to regenerate from. Rebuilding them is tracked
  separately — the markdown above is the current truth in the meantime.

## [1.3.1] — 2026-07-17

### Changed — docs sync

- README's three app blurbs caught up with today's app releases: the
  Glossary Generator's schema browser now carries ER diagrams (1.10.x),
  the Policy Generator runs the full Data Identification lifecycle incl.
  Deploy + Drift-check (1.8.x), and Catalog Insights ships 18 built-in
  dashboards with a per-view demo-data option (1.15.x). No script changes.

## [1.3.0] — 2026-07-17

### Changed

- **Both bootstraps build every app's React UI** — a shared `Build-Ui` /
  `build_ui` helper builds `frontend/dist` for the Glossary Generator
  (new in its 1.10.0), the Policy Generator and Catalog Insights when the
  checkout is fresh or just moved commits; without npm each app falls back
  to its legacy UI / API docs with a warning.
- INSTALL.md gained the two-lane (Windows host / Ubuntu VM) install-order
  diagram.

## [1.2.0] — 2026-07-17

### Changed

- **Catalog Insights moves to port 5002** (was 8660) — the demo host now
  runs a clean sequence: 5000 Glossary · 5001 Policy · 5002 Insights.
  Bootstraps, README, INSTALL.md updated; Insights 1.11.0 ships the new
  default and a first-class `run.ps1` launcher, which the docs and the
  installers' next-steps now point at instead of `run.bat`.
- **Docs lead with the Windows 11 host** — README's one-command sections
  reordered (apps on the Windows host first, the Ubuntu VM lab second) to
  match the standard demo topology.

## [1.1.0] — 2026-07-17

First versioned release of the repo (the content predates the numbering).

### Added

- **Catalog Insights joins the bootstrap** — `install-pdc-demo.ps1` and
  `install-pdc-demo.sh` now stand up all three apps: they clone/update
  [PDC-Insights](https://github.com/jporeilly/PDC-Insights) beside the
  Glossary and Policy apps and seed its `.env` with
  `PDC_BASE_URL=https://pentaho.io` (TLS verify off) on first run.
- **INSTALL.md** — the consolidated end-to-end guide: topology
  (Windows host apps + Ubuntu VM lab/PDC at 192.168.1.200), one-command
  installs for both sides, PDC connections, ports at a glance,
  troubleshooting pointers.
- **VERSION.md / CHANGELOG.md** — this repo now tracks its own version.

### Fixed

- **Policy Generator installs now include the React UI** — both bootstraps
  sparse-clone `frontend/` alongside `policy_generator/` (pre-1.7 checkouts
  are widened on update) and build it when npm is available; without Node
  they warn instead of silently installing an app with no UI.
- `data_sources/lab/README.md` — scenario table now lists all four
  verticals (was CSCU only); the PDC-VM-TROUBLESHOOTING.md and
  `pdc-reset.sh` links point at the Glossary repo where those files
  actually live (they were dangling relative links).
- Root README — the estate diagram and text now show all four repos and
  three apps (incl. Insights :8660); fixed the mangled `.\run.ps1` line in
  the Windows section.
