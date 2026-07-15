# Glossary Generator — Tags & the Domain Pack

*Copper State Credit Union (CSCU) courseware · companion to the Dictionary and Glossary review steps*

Explains where the **Suggested_Tags** on the review grid come from, why some rows show
only a generic tag, and how to enrich the vocabulary with a **domain pack** — the
supported way to make tags meaningful without introducing drift.

---

## 1. Tags are governed, not guessed

The tags on each term come from a **controlled vocabulary** (the Dictionary), not from the
LLM. They're built deterministically from:

- the term/column **name, term text, and category**, matched against the dictionary's
  **rules** (`pattern → tags`);
- the **category tag** for the term's category;
- structural signals — PII type, HIGH sensitivity → `maskable`, CDE → `cde`, key →
  `identifier`.

Everything stays inside the dictionary's allow-list, so tags can't drift into free-text.
**Enrich with LLM does not change tags** — it improves definitions and purposes. If you
want richer tags, you enrich the *vocabulary*, not run the LLM.

## 2. Why some rows show only "document" (or a bare category tag)

A term only gets a domain tag if **a rule matches its name/term/category**. Out of the
box the generic rules cover common domains (billing, contact, location, identifiers,
compliance). Anything the rules don't recognise falls back to just the **category tag**.

For CSCU's document store that would mean most folders — loan applications, statements,
ACH batches, KYC files, SAR summaries — showed only `document`, because no generic rule
names them. That's a **vocabulary coverage gap**, not a bug: the tagging works, the
vocabulary was just thin for financial-services domains.

## 3. The domain pack fixes it

The CSCU pack (`credit_union.example.json`, installed as `domain_pack.json` beside
`suggester.py`) extends the governed vocabulary with pre-approved financial rules so
CSCU's database columns and document folders get real tags:

| Column / folder / name matches | Tags |
| --- | --- |
| card, PAN, CVV, MCC, expiry | `pci · card · payments` |
| ACH, routing, wire, SWIFT, IBAN | `payments · ach` |
| KYC, AML, SAR, suspicious, OFAC, risk rating | `compliance · aml` |
| loan, APR, collateral, principal, maturity | `lending · credit` |
| ledger, journal, GL, debit/credit amounts | `ledger` |
| fraud, dispute, chargeback, reversal | `fraud · compliance` |
| statement | `statement · records` |
| correspondence, letter, notice, memo | `correspondence · records` |
| dividend, APY, interest rate, rate sheet | `rates` |
| member, joint owner, beneficiary | `member` |
| deposit, savings, checking, share draft, certificate | `deposit` |

Tags introduced by the pack are **company-layer and pre-approved** — governed, so they
count as allow-listed vocabulary rather than pending drift. The rules apply to database
columns too, not just documents: `cards.cvv_cd` picks up `pci`, `ach_payments.ach_rte_no`
picks up `payments · ach`, and so on.

### Pack format

```json
{
  "domain": "credit_union",
  "category_tags":  { "Compliance & Risk": ["compliance", "aml"] },
  "extra_tags":     ["pci", "ach", "kyc", "..."],
  "tag_rules": [
    { "pattern": "\\bcard\\b|\\bpan\\b|\\bcvv\\b", "tags": ["pci", "card", "payments"] }
  ]
}
```

- `tag_rules` — `pattern` is a regex matched (case-insensitive) against name+term+category;
  `tags` are added when it matches. These are the main lever.
- `extra_tags` — tag names to add to the allow-list even if no rule references them yet.
- `category_tags` — the tag(s) every term in a category receives.
- Override the file location with `GLOSSARY_DOMAIN_PACK`.

The full CSCU pack (both the tag half and the categorization half — table→category,
table→term, abbreviations like `mbr`→Member and `apr`→APR) ships in
`data_sources/CSCU/domain_pack/` with a ready-to-install zip.

## 4. Applying pack changes — the two-step refresh

The dictionary is seeded once and then persisted (`tag_dictionary.json`), so editing the
pack does **not** retroactively change a running catalog. After adding or changing
`domain_pack.json`:

1. **Dictionary page → Reseed** — rebuilds the vocabulary from the generic baseline + the
   pack. (This discards un-approved scan-grown additions; approved/steward items are the
   governed set.)
2. **Glossary grid → Suggest tags** — re-derives `Suggested_Tags` for the shown rows from
   the refreshed vocabulary.

Then the rows pick up the new domain tags.

## 5. Governance — how new tags stay controlled

- Pack rules and their tags are **company-layer, pre-approved** → immediately governed.
- Tags/terms **grown from scans** enter as **pending** and only govern the Registry once a
  **steward approves** them on the Dictionary page. So the vocabulary grows under review,
  never silently.
- The governed set is what flows into the Registry and (via the Policy Generator) into
  PDC Data Identification — keeping tags, terms and classification drawn from one
  allow-list. Extending the domain pack is the clean way to widen that set.

---

### Reading the Search facet preview (and when to retire a tag)

The Dictionary page previews how the governed tags will look as **OpenSearch
facets** in PDC (a filter on `attributes.tags.name`). Read it correctly:

- **The counts are reviewed usage inside this app** — accreted on every scan —
  **not live PDC data**. "Empty" means *no reviewed scan row has carried the
  tag since the dictionary was last (re)seeded*; it does **not** mean no PDC
  asset carries it.
- **Every tag empty at once = freshly reseeded**, not broken. A dictionary
  reseed (scenario reinstall, the Reseed button) zeroes the counters; the next
  scan + review cycle rebuilds them.
- **Retire nothing right after a reseed.** After a full scan of *every*
  source, tags still empty are genuine facet clutter — the panel's **Retire
  empty company tags** button removes them in one click (audit-logged). The
  generic baseline is protected, and a tag a rule still emits is re-added
  with a warning, so the vocabulary can't break.
- **Where the policies fit.** When the drafted Data Identification methods
  run, they stamp these governed tags onto real PDC entities — PDC's *actual*
  facet fills from policy runs regardless of this preview. The authoritative
  "this tag is dead" signal is the Policy Generator's **drift-check** (its
  reconciliation half): deployed methods' Assign-Tags and PDC's live facet
  compared against the Registry vocabulary. Until that ships, the
  after-full-scan rule of thumb above is the manual equivalent.

---

### The pack generator — the pack learns from the scans

Packs start hand-authored, but they don't stay that way. After a full scan +
review cycle, **Dictionary → Export domain pack** exports the reviewed state
back into pack format — the flywheel that makes each cycle better than the
last:

- **What it learns**: table→category mappings and table record terms from the
  reviewed rows; `cat_keywords` from table tokens; **abbreviations** by
  aligning column tokens with term words (`mbr_no` + "Member Number" →
  `mbr: Member`, two sightings required); the **governed company vocabulary**
  (approved terms/tags/rules only — pending scan noise never exports); and
  **`curated_seeds`** carrying the scan's induced value patterns and profiled
  reference lists per term — detection seeds specific to *this* company's
  data, which flow into the Registry (`source: "curated"`) for the Policy
  Generator.
- **Merge, never silently overwrite**: learned content fills gaps and adds
  new entries, and every place the scan *disagrees* with the installed pack
  is listed in the export dialog as a checkbox row — pack value vs scan
  value, the steward picks the winner. Defaults: curation-bearing keys keep
  the pack's value (a steward's recorded decision beats the machine's newest
  opinion); `curated_seeds` prefer the **scan** — they're machine-derived
  evidence, so fresher profiling wins and the replaced seed stays visible.
  Term entries take safe unions: aliases/tags union in, sensitivity tightens
  automatically, and a *loosening* is surfaced as a conflict, never applied
  silently. Entries the steward **retired** in the dictionary (tombstoned —
  they stay retired through reseeds instead of resurrecting from the pack)
  appear as removal rows, default *remove* — so an over-eager Approve-all is
  recoverable per item (✕ retire / ⤵ fold-to-alias on the vocabulary tables)
  and the pack stops re-seeding the mistake.
- **Starting from nothing**: a new company doesn't need a hand-authored pack.
  Run packless (generic defaults), do one scan → review cycle, and the first
  **Export domain pack** *is* the base pack — commit it and every later
  cycle refines it through the merge above.
- **Two ways to use it**: **Apply to this app** (writes the pack — timestamped
  backup kept — and reseeds the dictionary; approved items survive), and
  **commit** the file to the scenario's `domain_pack/` folder so every future
  install starts from evidence instead of guesses. Do both — an uncommitted
  improvement dies with the install.
- **When**: after review, before you'd reinstall or hand the vertical to the
  next cohort. It exports the *reviewed* state, so the richer the review, the
  better the pack.

---

### Quick reference

| Want to… | Do this |
| --- | --- |
| Make a domain's terms tag meaningfully | Add a `tag_rules` entry to `domain_pack.json` → Reseed → Suggest tags |
| Add an allowed tag with no rule yet | Add it to `extra_tags` → Reseed |
| Change a category's default tag | Edit `category_tags` → Reseed → Suggest tags |
| Approve a scan-grown tag | Dictionary page → review pending → approve |
| Understand why a tag is bare | The name didn't match any rule — add one to the pack |
| Make the pack learn from this scan | Dictionary → Export domain pack → Apply / commit |

*All Copper State Credit Union data is fictional and generated for training.*
