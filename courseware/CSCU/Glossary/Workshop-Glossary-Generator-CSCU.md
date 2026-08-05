# Workshop — Build the Business Glossary with the Glossary Generator

*Copper State Credit Union (CSCU) scenario · app 1.10.x · validated against PDC 11.0.0*

**Primary role:** Data Steward / Solution Architect
**Estimated time:** 60–90 min
**Prerequisites:** the shared lab running with CSCU loaded
(`data_sources/lab` → `make up && make load SCENARIO=CSCU`),
PDC reachable over HTTPS, the CSCU domain pack installed
(`data_sources/CSCU/cscu-domain-pack.zip` → unzip into `glossary_generator/`).

---

## 1. The scenario

**Copper State Credit Union** is a fictional Arizona credit union with six
branches (Phoenix, Tempe, Tucson, Casa Grande, Globe, Prescott), ~13 pilot
members, and a core banking schema (`cscu_core`, 11 tables)
plus a document store (`cscu-documents` bucket, 18 files). Its data estate has
exactly the governance problems the Registry approach fixes:

- **PII everywhere** — SSNs, DOBs, card PANs, account and routing numbers spread
  across `members`, `cards`, `accounts`, `ach_payments`.
- **A planted PCI violation** — `cards.cvv_cd` stores card verification values,
  which PCI DSS forbids after authorization. Your steward review must catch it.
- **Cryptic core-banking names** — `mbr_no`, `prin_bal_amt`, `apr_rt`,
  `ach_rte_no`. The generator's abbreviation expansion (plus the CSCU pack)
  turns them into readable terms: *Member Number*, *Principal Balance Amount*,
  *APR*, *ACH Routing Number*.
- **A compliance story that spans sources** — SAR 97001 (structuring: two
  $9,450 transfers just under the $10,000 threshold) exists as database rows
  (`suspicious_activity`, `ach_payments`, `transactions`) *and* as documents
  (the Q2 SAR summary PDF, the ACH batch JSON). One glossary must cover both.

## 2. What you will build

An import-ready **business glossary** for PDC — one reviewed term per
business-meaningful column and document folder, each with governed tags
(`pci`, `aml`, `lending`, …), rule-based sensitivity, CDE flags, and steward
assignments — plus the **Registry** the Policy Generator will later read to
emit Data Identification methods.

## 3. Lab flow

### Step 1 — Stand up the sources

```sh
cd data_sources/lab
cp .env.example .env
make up                    # shared postgres + minio (all scenarios)
make load SCENARIO=CSCU    # cscu_core db + cscu-documents bucket, verified
```

`make console` reprints the PDC connection values (database
`CopperState_Core_Banking`, object store `CopperState_Documents`).

### Step 2 — Register the sources in PDC

Use the app's **bulk loader** (WORKFLOW ▸ **Connect** → Bulk-load data sources) with
`data_sources/CSCU/cscu-datasources.csv`, or create the two sources by hand.
Then run **Metadata Ingest → Profile → Data Identification** in PDC, and click
**Scan Files** on the document store. (Identify *once* — the steward's
overrides come later and must not be clobbered.)

### Step 3 — Install the scenario and start the app

Unzip `cscu-domain-pack.zip` into `glossary_generator/` (this drops
`domain_pack.json` and the `people.json` steward roster), delete any previous
`tag_dictionary.json`, then `.\run.ps1` (on the VM: `./run.sh`) and open
`http://127.0.0.1:5000`. Confirm on **Settings** (CONFIGURE ▸ Settings) that
`GLOSSARY_COMPANY=Copper State Credit Union`.

### Step 4 — Scan & review

On **Connect ▸ Schema**, connect to `cscu_core` (schema `cscu_core`,
read-only `pdc_user`) — the schema browser has a Cards | ER-diagram toggle —
and **Scan**; then on **Connect ▸ Files**, **Add to glossary** from the MinIO
bucket so one glossary spans both sources. On the **Review** page (the "How
to review" guide panel opens by default — it is a clickable flow: the
**Approve pending vocabulary** box hops to the Dictionary and back, the AI
agents appear as sequence chips that highlight the toolbar, and Govern
navigates onward; follow it in order, then work the grid):

- Check the expansions: `mbr_since_dt` → *Member Since Date*, `apr_rt` → *APR
  Rate*. Edit anything weak.
- Confirm sensitivity: `ssn`, `card_no`, `acct_no` must be HIGH. The profiler
  and the pack's sensitivity floors should already say so — verify, don't trust.
- **Find the planted violation:** `cvv_cd` on `cards`. Its column comment and
  the PCI attestation PDF both flag it. Keep the term, set sensitivity HIGH,
  tag `pci`, and note the remediation in the definition — the glossary is where
  the finding becomes visible to everyone.
- Check the tags the CSCU pack derived: `ach_rte_no` → `payments · ach`,
  `risk_rating_cd` → `compliance · aml`, statements folder → `statement ·
  records`. A bare `document` tag means a vocabulary gap — extend the pack,
  don't hand-edit. Tags are standardised **lower-case** (`pci`, never `PCI`) —
  they are search facets in PDC, and case variants would fragment the facet.

### Step 4a — Put the agents to work

The grid carries a set of local AI agents, grouped in the toolbar under
**AI AGENTS — kept rows · propose → you accept**: they run on the KEPT rows
only, and they share one contract — the deterministic rules run first, the
model only adds judgment, every proposal is guardrailed to the governed
vocabulary, and **nothing applies itself** — you click. Results land as
**inline click-to-accept pills** right on the affected cells, batch by
batch while the run streams (there is no proposal popup): accept a pill to
take just that change, or **Accept all / Dismiss all** from the strip above
the grid. The grid's **LLM** provenance pills appear only after a proposal
is accepted.

- **AI pass (all fields)** — the single grid agent. The model reads each row's
  *scan evidence* (the induced value format such as `^CSCU-\d{6}$`, profiled
  reference values, PII class, and why the scan proposed the term) and returns
  the definition, the purpose, a clearer business name (as a suggestion chip),
  governed tags, and a category *only* when the current one is blank — all in
  **one call per batch** of rows. Sensitivity and PII are never the model's to
  set: they stay deterministic from the scan.
  Expand a row and use **AI review** to re-run the same pass on that row alone.
- **Duplicate groups come with advice.** Every duplicate header now recommends
  **Merge / Disambiguate / Keep separate**, with the reason: a foreign key
  between the columns (same concept by construction), matching or conflicting
  induced formats, overlapping or disjoint code lists. **AI advise** escalates
  the ambiguous groups — it samples live values from the member columns over
  your connection and compares the actual populations, then lets the model
  adjudicate whatever is still unclear.
- **The definition linter rides along inside the pass** — circular, vague,
  echoed, copy-pasted and templated definitions are flagged *before* the model
  runs, and the flag is fed into the prompt as a **rewrite order**, so the pass
  returns a specific sentence instead of the scan's boilerplate. Rows are
  re-linted afterwards, so a QA ⚠ chip that survives is a definition the model
  could not improve from the available evidence — a real signal, not repeat
  noise. It is deterministic, so it still works with Ollama offline.
- **Find similar** — proposes same-concept merges across *different* names
  (`phone` vs `cust_phone_no`), and now reads the data evidence too: a shape
  match is marked *strong*, while look-alike names holding different data are
  flagged **different concepts** with the merge withheld.

### Step 4b — Steward judgment lab: work the *Find similar* list

Run **Find similar** with the threshold at its default **0.60** and merge
nothing yet. The point of this exercise: the advisor supplies *evidence*;
the steward supplies *meaning* — and at 0.60 the list deliberately contains
both. Work it top-down:

1. **The strong trio.** `Employee ID ← Manager Employee ID / Reviewer
   Employee ID / Filed By Employee ID` — each justified by a foreign key
   (*"same concept by construction"*). The FK proves the columns share a
   value domain: they all hold employee ids. Whether they are one **term**
   is a policy decision the tool cannot make:
   - *One concept, many columns* (PDC-native): merge all three — the
     `mgr_emp_id` column simply links to **Employee ID**.
   - *Role-qualified terms*: dismiss all three — **Manager Employee ID**
     carries meaning ("who approves") the bare identifier doesn't.

   Either is defensible; deciding the three **inconsistently** is not.
   Pick a policy, apply it to all three, record it in the surviving term's
   definition. If you merged, open the Dictionary page and run the **AI
   fold advisor** so the governed vocabulary folds the same way — the grid
   and the vocabulary must tell one story.
2. **The classic traps — dismiss each, and say why out loud:**
   `Balance Amount ← Available Balance Amount` (ledger vs available);
   `Account Number ← External Account Number` (ours vs the
   counterparty's); `Dr Amount ← Cr Amount` (opposites!); `Branch City ←
   Branch County`; `KYC Status ← SAR Status` (different regulatory
   processes). High string similarity, different business meaning.
   **Dismissing is the review** — each dismissal is a recorded decision
   the audit can defend.
3. **The junk pair.** `June Debits ← June Credits` — neither merge nor
   dismiss: period-specific spreadsheet noise. Untick their **Keep**
   boxes; they should never reach PDC at all.
4. Drag the **threshold to ~0.75** and watch the noise fall away — that is
   the working setting for routine passes; 0.60 was the teaching setting.

**Checkpoint:** you dismissed more than you merged. A cohort that merges
everything the advisor suggests has missed the lesson.

### Step 5 — Govern

The roster is pre-seeded with the CSCU team, each steward carrying the
expertise keywords the matcher uses. **Auto-assign all slots** and verify
the result: *Elena Ramirez* stewards **Member, Accounts & Deposits,
Transactions, Branch Operations**; *Marcus Webb* **Lending, Finance &
Ledger**; *Nadia Flores* **Compliance & Risk, Records & Documents**; *Tom
Callahan* **Cards & Payments**. Elena's Data Steward role fills the
**owner** slots, and *Omar Haddad* (Data Storage Administrator) fills every
**custodian** slot — every pick shows its confidence and matched terms.
Set ratings (Auto/DQ), review date, and status.

### Step 6 — Generate, import, resolve, apply

**Generate JSONL** (writes the Registry alongside), import it in PDC
(**Business Glossary → Actions → Import**), **Resolve term ids**, then
**Apply to PDC** — dry-run first, always. The Data Discovery watcher is
terminal-aware: it stops the moment PDC's worker finishes and prints a
per-file verdict — profiled ✓ / no-DQ-from-PDC / failed. The no-DQ verdict
is **expected** for the document files (pdf/docx types get no Data Quality
in PDC), so don't wait for 18 of 18. Finish with the Trust Score rollup.
Note on DQ in the app's tables: a column that was never profiled shows a
muted **DQ —** ("not profiled") chip and exports no `qualityScore` — a
NOT-NULL constraint alone never fabricates a 100.

Need an artifact on the VM? The generated JSONL and the drafted-policies
zip (Step 7) each carry a ghost **⇪ Send to lab (MinIO)** button that
uploads to bucket **`pdc-exports`** over a saved MinIO/S3 connection — the
connection must be **write-capable** (the cast user's lab key is
read-only, so use the admin key/secret). Grab it on the VM from the MinIO
console (`:9001`) or `mc cp` to `~/Downloads`.

### Step 7 — Draft the Data Identification rules

Still on the Govern page, click **Draft policies (AI)**. Every kept term whose
scan produced a detection seed becomes a ready-to-import PDC rule: the induced
`^CSCU-\d{6}$` becomes a **Data Pattern**, the profiled code lists (risk
ratings, SAR statuses, …) become **Dictionaries** with their values CSVs — one
zip, with an INDEX. The AI agent polishes each rule's column-name hint and tag
pick, guardrailed to the governed vocabulary. Review every rule, then import
under **Management → Data Identification** (the Technical Track's Module 03
teaches exactly what each field means).

## 4. Checkpoints

| # | Check | Evidence |
| --- | --- | --- |
| 1 | 11 tables + 18 documents scanned | Sources chip on the Review page |
| 2 | `cvv_cd` flagged HIGH / `pci` | The review grid row + your note |
| 3 | SAR terms marked CDE, HIGH | `suspicious_activity` terms |
| 4 | Tags all governed (no drift) | Dictionary page: 0 off-vocabulary |
| 5 | Stewards assigned per domain | Govern page slots |
| 6 | Registry written at export | `registries/registry.<glossary>.json` |
| 7 | Definition QA clean, policies drafted | QA panel empty · drafted-policies.zip |

## 5. Where the story continues

The Registry you just produced is the input contract for the **Policy
Generator**. Its *authoring* half already runs inside this app — **Draft
policies (AI)** turned your detection seeds into importable dictionaries and
patterns in Step 7. The remaining half — binding the rules to reconciled term
ids over the API and **drift-checking** deployed methods against the Registry
— is the separate Policy Generator session.

---

*All Copper State Credit Union data — members, accounts, transactions, SARs and
documents — is fictional and generated for training.*
