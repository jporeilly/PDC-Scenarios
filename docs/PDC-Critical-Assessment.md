**Pentaho Data Catalog — Critical Assessment (10.2.11, with 11.0 viability)**

**Gaps and Recommended Solutions**

*Based on hands-on AWC implementation and PDC 10.2.11 courseware development, updated 2026-07 with findings from a live PDC 11.0.0 build (the CSCU registry→methods pipeline, validated end-to-end). Each gap is assessed against PDC 11.0 in the Viability for Version 11 section — most persist.*

## **Executive summary**

PDC 10.2.11 is capable, but its defaults assume a small, manual, freeform catalog. Those assumptions break the moment you hit real enterprise scale — 100+ sources, thousands of columns, multiple stewards — and they quietly manufacture governance **drift**: the same concept classified three different ways, tags that don't match terms, glossary entries nobody agreed to.

The fix is not more manual effort inside PDC. It's a thin governance layer **on top of** PDC: a single Classification Registry as the source of truth, everything downstream (glossary terms, Data Identification methods, policies) generated from it, everything automated through the REST API, and LLMs used surgically for residual work only. This is the pattern already proven in the AWC build.

**Reference implementations** (public GitHub, validated against live PDC 11.0.0):

- [PDC-Glossary-Generator](https://github.com/jporeilly/PDC-Glossary-Generator) — the governed glossary side: scans sources, mints one term per concept, governs tags, and **writes the Classification Registry** this document keeps referring to.

- [PDC-Policy-Generator](https://github.com/jporeilly/PDC-Policy-Generator) — reads the Registry and owns the Data Identification lifecycle: **author → reconcile → deploy → drift-check** (custom methods only, GraphQL retire included).

- [PDC-Insights](https://github.com/jporeilly/PDC-Insights) — the read-only reporting layer this document keeps recommending: curated dashboards over the public API (trust, quality, sensitivity, coverage, lineage), with NL-to-dashboard generation via a local LLM. Built against 10.2.11, re-targeted at 11.0.

- [PDC-Scenarios](https://github.com/jporeilly/PDC-Scenarios) — the training verticals that exercise the apps end-to-end: data kits, domain packs, and per-scenario courseware, deployed with one command.

The gaps below are ordered roughly by pain-at-scale.

## **Gap summary**

| **\#** | **Gap**                                                | **Impact**                                                                                   | **Recommended solution**                                                                   |
|--------|--------------------------------------------------------|----------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| **1**  | No bulk data-source onboarding                         | One-at-a-time connections don't survive 100+ sources                                         | Config/CSV-driven bulk loader via API                                                      |
| **2**  | Manual JDBC driver management                          | One-time staging toil per source type — friction, not a show-stopper                        | Auto-provision the correct driver per source type + version (fold into the bulk loader)   |
| **3**  | Raw metadata-ingest metrics shown to analysts          | Noise; means nothing to a BA                                                                 | Role-scoped, curated views (surface decisions, not counts)                                 |
| **4**  | Auto/freeform glossary                                 | Concept drift, duplicate terms                                                               | Curated glossary; mint one governed term per table                                         |
| **5**  | No registry linking glossary ↔ classification          | Two freeform surfaces drift apart                                                            | Classification Registry that syncs both                                                    |
| **6**  | Native dictionaries/patterns used as-is                | Industry mismatch + drift                                                                    | Custom, company/industry policies from the registry                                        |
| **7**  | No real policy objects                                 | "Policy" is just an ad-hoc method combination                                                | Enforce governance upstream, generate combinations                                         |
| **8**  | Tags vs terms not enforced                             | Identical labels required but unchecked                                                      | Generate both from one source                                                              |
| **9**  | Trust Score entity limits                              | Columns/folders carry no native score                                                        | Derive/roll up scores via API                                                              |
| **10** | Built-in visualization is generic                      | Analysts can't self-serve what matters                                                       | API-driven read-only dashboards                                                            |
| **11** | Manual toil everywhere                                 | Slow, error-prone, unrepeatable                                                              | Automate onboarding, authoring, reconciliation, drift-linting                              |
| **12** | LLM misuse risk                                        | Non-deterministic classification erodes trust                                                | LLM as residual only; rules always win                                                     |
| **13** | UX isn't industry-standard or workflow-logical         | Deep nav, inconsistent terms, no guided flows                                                | Redesign around the data lifecycle; role-based, task-first                                 |
| **14** | No config-as-code / environment promotion              | Can't reliably move governance dev→test→prod                                                 | Registry as the versioned artifact; deploy per env via API                                 |
| **15** | No classification explainability                       | "Why is this column tagged X?" is unanswerable                                               | Emit provenance (rule vs LLM, confidence) in the envelope                                  |
| **16** | No bulk remediation or pre-deploy validation           | Drift fixed one asset at a time; deploys untested                                            | Reconcile modes for bulk fixes; dry-run against a sample import                            |
| **17** | Custom properties are ungoverned                       | Free-text properties drift independently                                                     | Registry-owned properties with pick-list values; required-property coverage                |
| **18** | Metadata rules have no guardrails                      | Rules encode drift; no impact preview or precedence                                          | Source rule values from registry; impact preview; conflict precedence; lint rule outputs   |
| **19** | Galaxy browses but can't answer relationship questions | "What does steward X own?" / "how are X and Y related?" have no direct path                  | Query the catalog as a graph; question-first ownership/path lenses                         |
| **20** | Lineage has coverage blind spots, no impact-set export | Non-emitting transforms produce no lineage; gaps invisible; impact analysis manual           | Push lineage via OpenLineage; coverage metric + impact sets + staleness from the graph API |
| **21** | Unstructured discovery needs an ML/LLM you feed        | Default models are narrow (English, financial/contractual); real coverage needs a custom LLM | Configure a local LLM; scope English-only; drive classification terms from the registry    |
| **22** | Similarity detection is remedial, not preventive       | Near-duplicate terms are flagged only after they're in the glossary — drift already happened | Check similarity at entry in the registry; PDC similarity becomes a backstop               |

## **1. Onboarding doesn't scale — build a bulk data-source loader**

Creating connections one at a time is fine for a demo and untenable in production. At 100+ sources the manual UI flow becomes the single biggest onboarding cost, and it's the least valuable use of a steward's time.

**Solution.** A bulk loader driven by a config/CSV manifest (host, port, type, credentials reference, root types) that provisions connections through the REST API rather than the UI. The same /entities/filter + \_ROOT_TYPES pattern already used to *read* data sources should have a symmetric *write* path for onboarding. Idempotent by design, so re-running a manifest reconciles rather than duplicates.

## **2. JDBC drivers should be auto-provisioned**

Onboarding stalls on driver management: the operator has to know which driver, which version, and stage it manually before a connection will validate. This is undifferentiated work that the platform has enough information to do itself.

**Solution.** Key driver provisioning off the declared source type and version. When a source is registered as, say, PostgreSQL 15 or Oracle 19c, PDC should resolve and stage the matching JDBC driver automatically. At minimum, ship a bootstrap step in the bulk loader that fetches the correct driver per manifest row so onboarding is a single action.

In practice this has proven to be **friction, not a show-stopper**: driver staging is a one-time cost per source *type*, not per source, so it doesn't scale with the estate the way connection creation does. It's demoted accordingly in the Prioritization section — worth folding into the bulk loader eventually, but not on the critical path.

## **3. Analysts are shown ingest metrics that mean nothing to them**

A metadata ingest produces a large volume of technical metrics. Dumping all of it into the analyst's view is noise. A business analyst does not need row counts, scan durations, or profiling internals — they need to know: *can I trust this, is it sensitive, who owns it, where did it come from.*

**Solution.** Role-scope the surface. Ingest metrics belong to the admin/engineer view. The analyst view should present only decision-relevant signals — trust, sensitivity classification, ownership, lineage — and suppress the rest. This is exactly what the read-only [Insights app](https://github.com/jporeilly/PDC-Insights) does: it reads PDC via API and renders a curated dashboard instead of the raw catalog.

## **4. The glossary should be governed, not auto-generated**

Freeform, auto-populated glossaries are the primary source of concept drift. Two ingests produce two near-identical terms; nobody agrees which is canonical; downstream links fork. Auto-generation is only safe when the scope is very specific and small.

**Solution.** Curate the glossary. Mint **one conceptual term per table** as a creation-only step, and let the steward link it deliberately — never auto-link. This keeps the glossary small, intentional, and reviewable, and it's the behaviour the [Glossary Generator](https://github.com/jporeilly/PDC-Glossary-Generator) app already enforces.

## **5. There is no registry tying the glossary to classification — add one**

This is the core architectural gap. PDC has a glossary surface and a Data Identification surface, both freeform, with no shared source of truth. So they drift independently. Tag drift, specifically, is the *sole* remaining drift surface once everything else is generated — because tags are free text on both the glossary side and the Assign Tags side, and PDC enforces no consistency between them.

**Solution.** A **Classification Registry** as the single canonical source: one entry per concept carrying the glossary term ID, the governed tag set, and a sensitivity floor. Both the glossary payload and the Data Identification method's Assign Tags are *generated from that one entry*. Governance is enforced upstream, in the registry, not hoped-for downstream. A controlled allow-list closes the tag-drift surface; a drift linter (reads the deployed method JSON, diffs Assign Tags against the registry) catches anything that slips.

## **6. Don't use the native dictionaries and patterns as-is — build a governed two-tier set**

The built-in data dictionaries and patterns are generic and lead straight to drift, because they classify by their own logic rather than your governed concepts. They also don't fit a specific industry. And PDC's dedicated ML *PII Detection* feature — the one that auto-detects names, addresses, and ID numbers and builds the ML_PII glossary — is a language-trained model that ships **only for Korean and Japanese** content (its API exposes just those two languages). There is no English or other-language PII model, so for English structured data that ML detector isn't available at all; native English PII classification falls entirely to dictionaries and patterns — which, in their generic native form, are exactly the drift-prone set this section is about.

The answer is *not* "everything is bespoke." It's a **two-tier set**, both tiers owned by the registry:

- **Tier 1 — a universal baseline** that applies to every industry: the structural identifiers that are the same everywhere (email, phone, national ID, payment card / IBAN, IP address, coordinates, dates). Maintain this as one governed common set so every project starts from the same trusted floor instead of re-deriving PII detection.

- **Tier 2 — industry / company extensions** layered on top (AWC's meter IDs, service-territory codes, tariff classes, and the like).

The discipline is the same for both tiers: **a "generic" set left freeform drifts exactly like a bespoke one.** The baseline must be versioned, allow-listed, and registry-owned — not a loose pile of patterns everyone edits. Tier 1 gives you reuse; the registry keeps Tier 1 from becoming its own drift surface.

**Solution.** Author and stage both tiers from the registry so every dictionary and pattern traces back to a governed concept. Respect the two import contracts precisely — **as live-validated against a running 11.0 build (2026-07), which corrected every detail the docs and training materials implied**:

- **The import format is PDC's own Export format** — not the Rules-tab display JSON, and not what the documentation images show. The only reliable way to learn the contract is to export a built-in method from the target build and mirror it byte-for-byte; docs lag builds.

- **Dictionary artifact** — the upload zip contains one **nested `<name>.zip` per dictionary**, each pairing the envelope JSON with its values CSV (header row `Term`). `dictionaryTermId`, bitset and HLL fields are **server-computed: omit them** — the term link travels as `assignBusinessTerm: [{name, id}]` inside the rule's action.

- **Pattern artifact** — the upload zip contains **flat `<name>.json` files**, one per pattern. Each JSON file is a **single envelope object**; PDC's importer Gson-parses per file and rejects arrays outright (`Expected BEGIN_OBJECT but was BEGIN_ARRAY`).

- **Tag/term actions** — `applyTags: [{"name": tag}]` (the older docs' `{"k": …}` shape is silently wrong on 11.0), and the import validator requires a tag in **every** action object — `assignBusinessTerm` must ride in the *same* action object as `applyTags`, or the import fails with "No Tag found in Rule".

- **Weight-format quirk (real, but inverted from what the training materials suggest):** pattern confidence weights are strings while dictionary weights are numbers, and condition thresholds are the reverse. Mirror the export sample exactly rather than reasoning about it.

- **The `minSamples` trap** — built-in envelopes carry `minSamples: 200`. Copy one verbatim and your method imports green, binds its term, and then **silently stamps no tags** on any column with fewer than 200 sampled values. Set it deliberately (1 for demo-scale, tuned upward for production).

Use a stable uuid5(NS, "AWC\|kind\|concept") \_id so upserts are idempotent and re-deploys reconcile instead of duplicating — **now proven live: a re-import with the same \_id cleanly overwrites the deployed method in place.**

## **7. "Policies" aren't real objects — enforce governance upstream**

There are no pre-built named policies in PDC. A policy is simply a combination of methods a user selects at runtime. That means there is nothing in the platform to enforce which methods constitute a governed policy — it's convention, and convention drifts.

The 11.0 internals confirm how thin this is: identification methods are rows in two Mongo-style collections (`dictionaries`, `datapatterns`) behind a GraphQL CRUD endpoint — on 11.0 those collections are served by **FerretDB, PostgreSQL-backed** (the MongoDB → FerretDB migration in the gotchas table), with the Mongoose/GraphQL layer unchanged above it — and "policy" never exists as an object anywhere: it is literally whichever checkboxes a user ticks at **Select Methods** before a run.

**Solution.** Treat the method combination as a generated artifact, not a manual choice. The registry defines the governed set; the tooling emits the combination; the analyst applies a known-good policy rather than assembling one ad hoc. The working form of this, exercised live in the CSCU build, is a **custom-only run policy**: every method is authored from the registry under a common prefix, and identification runs select *only* the prefixed set — never the built-ins — so every stamped tag traces to a versioned, evidence-based method.

## **8. Tags and terms must be identical — but PDC won't enforce it**

Governance requires the tag label and the term label to match exactly, yet PDC does not enforce that consistency. Left to hand-entry, they diverge.

**Solution.** Never hand-enter both. Generate the tag and the term from the same registry entry so identical labels are guaranteed by construction, not by discipline.

## **9. Trust Score doesn't reach columns or folders**

Trust Score is native only to tables and files. Columns and folders never carry a score natively — but those are often exactly the granularities an analyst reasons about.

**Solution.** Derive the missing granularities via API: roll table/file scores up to folders and, where signal exists, down to columns, and expose the derived score in the curated analyst view. One caveat confirmed in the docs: the native Trust Score isn't currently exposed in the public API, so compute rollups from its input signals — data quality, lineage-verified, user rating, term-assigned — rather than reading the score directly. PDC won't give you column/folder scores natively, so compute them in the layer on top.

## **10. Visualization should be API-driven, not the stock UI**

The built-in views are generic and can't be tailored to what a given audience needs to see. The API can.

**Solution.** Build read-only dashboards on the REST API. The proven access pattern is Keycloak bearer auth (POST /keycloak/realms/pdc/protocol/openid-connect/token, client_id=pdc-client → access_token) followed by POST /entities/filter with the appropriate root types. This is how the [Insights app](https://github.com/jporeilly/PDC-Insights) renders curated dashboards, live panel previews, and generated views without touching the catalog UI.

## **11. Automate the manual toil — the API is the product**

Almost everything above is currently manual. Manual onboarding, manual method authoring, manual reconciliation, manual drift checks. Each is slow, error-prone, and unrepeatable across environments.

**Solution.** Automate through the API end to end:

- **Onboarding** — bulk loader (Gap 1; fold driver staging, gap 2, in when convenient).

- **Authoring** — idempotent method upserts keyed on uuid5 \_id.

- **Reconciliation** — full-catalog reconcile across the four coverage modes (UNKNOWN, UNLINKED, DRIFT, MISSING) so gaps are surfaced systematically, not spotted by eye.

- **Drift-linting** — read deployed method JSON and diff Assign Tags against the registry on every deploy.

The automatable surface on 11.0 is broader than the public docs suggest (all live-confirmed):

- One **Keycloak bearer token** (`client_id=pdc-client`) authenticates **both** the public REST API **and** the Apollo **GraphQL endpoint at `{pdc}/graphql`** that PDC's own UI uses. The authenticated OpenAPI spec is served at `/api/public/v3/openapi.json` (the conventional `/v3/api-docs` path just returns 401).

- The GraphQL endpoint exposes the **full method lifecycle** — list, update, and **delete** (`DictionariesRemoveById` / `DataPatternsRemoveById`) — including operations the UI has no button for. Introspection is disabled in production, but Apollo's "Did you mean …" validation errors enumerate the real field names on request.

- Two hard edges remain: the internal `/api/start-job` rejects public API tokens (401 — job triggering stays a UI step), and the built-in Is Primary/Foreign Key metadata (`metadata.column.*`) is harvest-owned and cannot be PATCHed; the writable alternative is `attributes.extended.*`.

If a step is done more than once, it should be a script against the API, not a click path.

## **12. Use LLMs surgically — rules always win**

LLMs are valuable but non-deterministic. If an LLM can *lower* a classification, trust in the catalog collapses.

**Solution.** Rules-first, LLM-residual. A rules pass classifies what it can; the LLM only handles the residual. Sensitivity is an **ordinal floor**: rules can only *raise* a classification, and the LLM residual can never lower a rule hit. Use the LLM for genuinely fuzzy work — name normalization across underscores, hyphens, camelCase; disambiguating residual columns — and run it locally (e.g. Ollama) for data residency. The LLM assists classification; it never owns it.

## **13. The UX needs a redesign, not a re-skin**

The interface isn't user-friendly and doesn't meet industry standards for a governance product. The problems are structural, not cosmetic:

- **Navigation is deep and non-obvious.** Common tasks are several clicks in and assume the user already knows where a feature lives. There is no task-first entry point.

- **Terminology is inconsistent across modules.** The same concept is named differently in different places (the product itself has had to consolidate labels — e.g. "Properties" vs "Custom Properties" — which is a symptom, not the disease). Inconsistent vocabulary is exactly what a *catalog* should never ship.

- **No guided flows for multi-step work.** Onboarding a source, authoring a classification method, or standing up a policy are inherently sequential, but the UI presents them as scattered forms rather than wizards with progressive disclosure.

- **One crowded surface for every persona.** A business analyst and a data developer see broadly the same dense screens. Role should change the *shape* of the workflow, not just hide a few buttons.

- **Weak empty states and no next-best-action.** New users land on screens that don't tell them what to do first.

Two exhibits from the live 11.0 build make the point concrete:

- **You cannot delete an identification method from the UI.** The Data Identification method list's ⋮ menu offers only *View* and *Edit* — no Delete — even though the `…RemoveById` mutations exist and work on the GraphQL endpoint directly behind that same screen. A whole lifecycle verb is missing from the surface while the platform supports it.

- **The Edit form loses data it should display.** Editing an imported dictionary or pattern does not hydrate the rule's JsonLogic condition — the field shows empty (and *required*) even though View → Rules displays the condition and the engine evaluates it. A steward who saves from that form is one click from persisting a blanked condition.

**Solution — redesign around the data lifecycle.** Reorganize the entire experience into the logical order people actually work in, and land each persona in the stage they own:

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>Onboard → Ingest → Classify → Govern → Publish → Monitor</p>
<p>(bulk) (scoped) (registry) (approve) (products) (curated insights)</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Concretely: a role-based home that opens on the user's stage; wizardized multi-step tasks (onboarding, method authoring, policy assembly) with progressive disclosure; a shared component **and copy** library so terminology is identical everywhere by construction; bulk actions and steward task-queues as first-class citizens; empty states that surface the next best action. The v11 UI-Kit alignment is a prerequisite for this, not a substitute — consistent components don't fix an illogical workflow.

Where PDC's native UX falls short of this, front it with the API-driven apps that already impose the right workflow: the [Glossary Generator](https://github.com/jporeilly/PDC-Glossary-Generator), the Registry-driven [Policy Generator](https://github.com/jporeilly/PDC-Policy-Generator), and the read-only [Insights app](https://github.com/jporeilly/PDC-Insights) collectively deliver the lifecycle order the native UI doesn't.

## **14. No config-as-code or environment promotion**

Governance artifacts — glossary terms, classification methods, policies — can be imported and exported, but only as opaque bundles. There is no diffable, versionable, CI-friendly way to promote a known-good configuration from dev to test to production. Every environment drifts from every other.

**Solution.** Make the registry the versioned artifact. It lives in source control, it diffs cleanly, and it deploys per-environment through the API with idempotent uuid5-keyed upserts. Promotion becomes "run the manifest against the next environment," not "export a bundle and hope."

This is no longer a proposal — it's a **proven pattern** on 11.0: registry in git, deterministic uuid5 `_id`s on every generated method, and re-import confirmed live to overwrite the deployed method in place (a clean upsert, no duplicates). The one lifecycle case an upsert can't cover — a concept *leaves* the registry, orphaning its deployed method — is handled by a scoped delete over the GraphQL endpoint (built-ins refused, name-prefix-scoped).

## **15. Classification decisions aren't explainable**

When a column ends up tagged, there is no trail explaining *why* — which method matched, whether a rule or the LLM produced it, or at what confidence. For a governance tool that is a serious gap: stewards can't defend a classification and can't debug a bad one.

**Solution.** Emit provenance in the method envelope: record rule-hit vs LLM-residual, the matching concept, and confidence, so every classification is traceable to its cause. Confirming the envelope field names against a live import sample is exactly the gate that makes this reliable — a gate now executed: the 11.0 envelope schema is captured from live exports, and the registry already carries seed-level provenance (`source: profiled | curated`) on every detection seed, so each deployed rule traces back to the evidence that authored it.

## **16. No bulk remediation or pre-deploy validation**

Drift is fixed one asset at a time through the UI, and methods and policies are deployed with no dry-run — you find out they were wrong after they're live.

**Solution.** Use the four reconcile modes (UNKNOWN, UNLINKED, DRIFT, MISSING) to remediate coverage gaps in bulk, and validate every deploy against a sample import before it ships — a dry-run that diffs generated Assign Tags against the registry and fails on drift. Backfilling stable term_id values is what makes bulk remediation idempotent rather than destructive.

The first pieces of this layer now exist and have run against live 11.0: a batched **term-id reconcile** (each registry concept looked up in PDC and badged verified / resolved / mismatch / missing — a full 124-concept registry reconciled and id-stamped in one pass), and a **scoped bulk retire** (delete every method under a name prefix via GraphQL) as the first bulk-remediation primitive.

## **17. Custom properties are another ungoverned drift surface**

Custom properties are, quietly, the same problem as tags and terms wearing a different hat. A property like *Data Owner*, *Retention Class*, or *Classification* entered as free text drifts immediately — "Confidential" vs "confidential" vs "COMPANY CONFIDENTIAL" — and now it drifts *independently* of the glossary term and the Assign Tags value. Every ungoverned property is a new surface where the same concept forks. PDC has shown it *can* do controlled values (the glossary "Classification" property ships with an enumerated Private / Public / Company Confidential list), but general custom properties are freeform, and there is no single schema describing which properties should exist, on which entity types, with which allowed values.

Two further gaps compound it: there is no enforcement of **required** properties (a table can be published with no Owner and no Retention Class), and properties are descriptive rather than actionable unless a rule picks them up.

**Solution.** Bring custom properties into the registry as first-class governed objects. Define, per entity type, which properties exist and their **allowed values as pick-lists**, and generate them from the registry so "Confidential" has exactly one spelling everywhere. Make required properties part of coverage: the reconcile MISSING mode should flag any governed entity lacking a mandatory property, not just a missing method or term. A property that can only be chosen from a governed list cannot drift.

## **18. Metadata rules are a powerful authoring surface with no guardrails**

The Rules Engine is genuinely useful — definitions are decoupled from rules, so one definition with multiple actions can be applied across many data sources in a few clicks, and 11.0 lets you build criteria by picking a classification, then related objects, then attribute conditions. But that power cuts both ways, and three gaps matter:

- **Rules are a fourth place the same string must match.** If a rule's *condition* or *action* references a tag, term, or property value as free text, that value now lives in the glossary, in Assign Tags, in the property, *and* in the rule — four surfaces, one concept, no enforced consistency. A rule that sets Sensitivity = "Confidental" (typo) silently propagates drift at scale.

- **No impact preview.** You apply a rule across all applicable data sources and discover afterward which assets it touched. There is no dry-run answering "which assets would this rule change, and how?" before it fires.

- **No conflict or precedence model.** At scale, rules overlap. When two rules set the same property to different values, which wins? Undefined precedence is drift-by-conflict, and it's invisible until someone notices the wrong label.

**Solution.** Treat rules as another *consumer* of the registry, not an independent authoring surface. Source rule condition and action values from the registry's governed vocabulary so a rule can't reference a value that doesn't exist. Require an impact preview (assets affected, before/after) before any rule is applied. Define explicit precedence for conflicting actions, and extend the drift linter to diff rule-set values — not just method Assign Tags — against the registry on every deploy.

## **19. Galaxy shows relationships but can't answer relationship questions**

Galaxy is a genuinely strong *explorer*. It consolidates data sources, glossary, reference data, applications, policies, the OT asset hierarchy, and metadata rules into one graph, distinguishes parent-child (solid) from association (dotted) edges, and offers expand/collapse, search, locate, filters, and per-node actions. But it's built for browsing, not asking, and three gotchas follow:

- **It answers "show me around," not "answer my question."** You can't ask *what assets does steward Jane own?* or *how is table X related to policy Y?* — you expand nodes and eyeball edges. Ownership and stewardship aren't pivots; they're buried attributes. The most common governance questions have no direct path.

- **Node limits cap completeness.** Rendering is limited to 25 / 50 / 75 nodes per hierarchy per node, applied separately to each hierarchy, with manual "load more." At enterprise scale you cannot see all of an asset's relationships at once — and nothing tells you the view is incomplete. A relationship beyond the cap is simply invisible.

- **It's a picture, not queryable data.** Galaxy output can't be filtered to "only owned-by edges," exported as an impact set, or fed into a report. Relationship intelligence stays trapped on the canvas.

**Solution.** Treat the catalog as a graph and *query* it. The relationships already exist behind the API, and v11 materializes lineage into an Apache AGE / PostgreSQL graph — expose them as question-first lenses in the read-only Insights app: "assets owned by steward X," "path between X and Y," "everything governed by policy Z," "terms with no linked assets." Ownership and stewardship become first-class filters, and answers are complete because they read the graph rather than a capped visual. Galaxy stays the exploration surface; the app answers what Galaxy can't.

## **20. Lineage is improving, but has coverage blind spots and no impact-set export**

Credit where due: v11 materially improves lineage — a materialized graph projection (PostgreSQL + Apache AGE) makes multi-hop queries faster and more complete, a hierarchical layout tames large graphs, and design-time, manual, and ML-model lineage extend coverage beyond runtime events. PDC also derives lineage from PDI (OpenLineage), Alteryx, Tableau / Power BI reports, and ML models. Real gains — but the structural gaps remain:

- **Coverage depends on the emitter.** Lineage is automatic only where the tool emits it. Transformations in warehouse SQL, dbt, stored procedures, or ad-hoc ELT produce none, so you fall back to manual lineage — design-time, hand-maintained, drifting from reality with nothing validating it.

- **Blind spots are invisible.** There is no lineage-coverage metric. You can't see which assets have lineage and which have none, so the gaps go unnoticed until someone needs a trace that isn't there.

- **Unresolved inputs become "representative" assets.** When PDC can't match a workflow input or output to a cataloged asset, it shows a representative node with incomplete metadata — lineage that *looks* connected but is shallow.

- **Impact analysis is manual.** You pick N upstream/downstream hops and read the graph. There's no one-shot "every downstream asset affected if I change this column" impact set to export for change management.

- **No staleness signal.** Runtime lineage reflects the last observed run; if a pipeline changes and isn't re-run or re-ingested, the graph is quietly stale with no indicator.

**Solution.** Push lineage from the tools that don't emit it — the OpenLineage route already explored (emit events from SQL / dbt / warehouse jobs, Marquez-style collection) — and add design-time lineage via API for the rest. Then treat lineage as data: read the AGE graph through the API to compute a **coverage metric** (assets with vs without lineage), generate **impact sets** for change management instead of clicking hops, flag **stale** lineage by last-event timestamp, and **validate manual lineage** against observed runtime to catch drift. Surface all of it in the read-only Insights app.

## **21. Unstructured discovery leans on an ML/LLM you have to feed**

Getting real value out of unstructured data — semantic document classification, summaries, address detection — depends on ML/LLM models, not simple scanning. PDC does ship built-in models, but they're narrow: the default document-classification model is trained on common financial and contractual document types (service agreements, NDAs, loan agreements, and the like), and AI-assisted document processing is **English-only** and skips scanned PDFs and images (those fall back to OCR). For anything outside that default — your industry's document types, other languages — you must configure a custom LLM. So unstructured governance is neither free nor offline by default: it carries an LLM dependency, GPU cost, and a data-residency question the moment documents leave the box.

**Solution.** Plan for a configured LLM rather than assuming the defaults cover you, and run it locally (Ollama) to keep documents in-house — the same residency posture as the structured LLM residual. Scope expectations honestly in the courseware: English-only, narrow default model, OCR for images. Then close the loop with the registry: document classification already takes business terms as its input and semantically matches against them, so feed those terms from the registry too — unstructured classification then draws on the same governed vocabulary as everything else.

## **22. Similarity detection is remedial, not preventive**

PDC's Metadata Similarity feature finds near-duplicate tables, columns, and business terms — but it runs as a **batch, after-the-fact** job. You select databases (and optionally terms), run the worker, then review suggestions on a *Similar Items* tab with a similarity score (default threshold 0.5) and approve or reject each one. Useful for cleanup — but by the time it flags a near-duplicate term, that term is already in the glossary. The drift has already happened; similarity only helps you mop it up.

So the instinct is right: to actually *prevent* term drift, the check has to happen **before** a term is committed, not after. Post-hoc similarity reduces redundancy; it can't stop it. It also carries its own quirks — rejecting a suggestion permanently excludes it from future runs, and the batch nature means results are stale between runs.

**Solution.** Put the similarity check at the point of entry, in the registry. When the [Glossary Generator](https://github.com/jporeilly/PDC-Glossary-Generator) mints a candidate term, compare it against the registry and existing terms *before* committing — the duplicate-group handling in the Review & prune grid is exactly this pre-commit gate. PDC's Metadata Similarity then becomes a backstop that should find almost nothing, not the primary defense. Prevention lives upstream; detection stays downstream as a safety net.

## **Further gotchas in features not yet covered**

The next tier of features carries its own traps. Same posture throughout — let PDC execute, own the governance and the gap-filling in the layer above.

| **Feature**                               | **Gotcha**                                                                                                                                                                                                                                                                        | **Solution / posture**                                                                                                                                                                                        |
|-------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Search + GenAI chatbot**                | Chatbot and NL search are beta and English-only; relevance is only as good as the underlying terms and metadata; GenAI can phrase a confident wrong answer                                                                                                                        | Ground search on the governed registry; treat the chatbot as assistive, never a system of record                                                                                                              |
| **Profiling & sampling**                  | User-guided sampling (row subset / WHERE clause) can produce non-representative stats — and those stats feed classification and Trust Score                                                                                                                                       | Standardize a sampling policy; flag low-confidence profiles; don't let a sampled profile silently drive a sensitivity decision                                                                                |
| **Trust Score & Data Quality dependency** | The Data Quality dimension of Trust Score is sourced from the separate **Pentaho Data Quality** product (OEM'd from DQLabs) — no PDQ means no DQ signal, and it's another product to license, deploy, and integrate; the overall score is also opaque and stale unless recomputed | Treat PDQ as a first-class deployment dependency; document the weighting for stewards; recompute on a schedule; show "last computed" — and note the score degrades to lineage/rating/term signals without PDQ |
| **Ingestion / OpenSearch init**           | opensearch-cluster-init fails when admin.crt isn't trusted by the node transport truststore — a silent deployment blocker                                                                                                                                                         | Append admin.crt to the node's extra.crt (already captured in pdc-reset.sh); read cert paths from container env                                                                                               |
| **11.0 FerretDB migration**               | 11.0 replaces MongoDB with FerretDB (PostgreSQL-backed): ~20 DBs / ~100 collections migrated via mongodump/restore plus PG schema consolidation, and ordering matters or the upgrade breaks                                                                                       | Treat as a planned migration: back up MongoDB and consolidate PG schemas *before* starting 11.0 services; rehearse on a copy                                                                                  |
| **Data Products SQL views**               | v11 SQL-view definitions aren't supported on secret-managed connections; governance metrics can be stale until refreshed                                                                                                                                                          | Avoid secret-managed sources for SQL-view collections; automate metric refresh at publish                                                                                                                     |
| **Entity Usage (v11)**                    | Pull-based usage capture supports only Snowflake, Oracle, and SQL Server; everything else needs the push API and instrumentation                                                                                                                                                  | Use the push API to fill coverage; don't assume usage analytics are complete out of the box                                                                                                                   |
| **Approval-workflow scope**               | v11 approval workflows cover the *glossary* lifecycle — generated classification methods and policies bypass them entirely                                                                                                                                                        | Mirror the approval gate in your registry deploy pipeline so methods get the same review as terms                                                                                                             |
| **DI import contract (11.0, live)**       | The import format is PDC's own **Export** format, not the docs' or the Rules-tab JSON: nested per-dictionary zips vs flat pattern JSONs, one Gson **object** per file (arrays rejected), `applyTags:[{"name":…}]`, a tag required in *every* action object                       | Export a built-in from the target build and mirror it exactly; keep the envelope templates versioned beside the registry                                                                                      |
| **`minSamples` default**                  | Built-in envelopes carry `minSamples: 200` — a copied method imports green and binds its term but **silently stamps no tags** on tables with fewer sampled values                                                                                                                 | Set `minSamples` deliberately per environment (1 for demo-scale data, tuned for production); include it in the pre-deploy dry-run checklist                                                                   |
| **Method delete missing from UI**         | The 11.0 method list's ⋮ menu is *View/Edit only* — no Delete — though `DictionariesRemoveById` / `DataPatternsRemoveById` work on the `{pdc}/graphql` endpoint behind the same screen                                                                                            | Delete over GraphQL (same Keycloak bearer), always scoped: filter by your method-name prefix and refuse built-ins                                                                                             |
| **Edit form drops rule conditions**       | The Dictionary/Pattern *Edit* form doesn't hydrate the rule's JsonLogic condition (shows empty + required) even though View → Rules displays it and it evaluates — a save can persist a blanked condition                                                                          | Never hand-edit imported methods; the governed change path is adjust-in-registry and **re-import** (deterministic ids make it a clean upsert)                                                                 |
| **GraphQL introspection disabled**        | Apollo introspection is off in production, so the UI's GraphQL schema looks undiscoverable                                                                                                                                                                                        | Apollo's validation errors ("Did you mean …") enumerate real field names when probed with wrong ones — a read-only discovery path needing only the bearer token                                               |
| **Rule-condition vocabulary**             | The condition builder exposes 8 variables (`metadataScore`, `confidenceScore`, `similarity`, `columnCardinality`, `dictionaryCardinality`, `intersectionCardinality`, `dictionarySimilarity`, `rowCount`) — barely documented, and the richer dictionary-specific ones go unused | Author conditions from the registry's profiling evidence (e.g. cardinality floors from observed value counts) instead of copying the built-ins' generic thresholds                                            |

## **Vendor-dependency risk: the DQLabs OEM**

Because the Data Quality dimension of Trust Score is sourced from Pentaho Data Quality — which is OEM'd from DQLabs — a slice of the catalog's trust signal rests on a third-party relationship you don't control. It's worth planning for what happens if that relationship ends.

**What breaks.** Trust Score loses its Data Quality input and degrades to lineage-verified, user-rating, and term-assigned signals only. Anything keyed off Trust Score or the DQ dimension — dashboards, rules, policies, data-product readiness gates — shifts underneath you, and scores computed with DQ stop being comparable to scores computed without it. Pentaho Data Quality itself would likely be frozen, replaced, or sunset: existing deployments may keep running on their last binaries but lose updates, new connectors, security patches, and support. And DQ rules authored in the DQLabs engine live in its format, so migrating them to a replacement is real work — classic OEM lock-in.

**Why it's timely, not hypothetical.** Pentaho changed hands in June 2026 (to LEO Software / Constellation). Ownership changes are exactly the events that put OEM agreements under review, so the prudent move is to reduce exposure now rather than react later.

**Mitigation — the same layer-on-top posture.** Don't let a single OEM component be load-bearing for governance:

- **Abstract the DQ source.** Put the DQ signal behind your own interface so DQLabs can be swapped for an alternative (native profiling-derived checks, Great Expectations, Soda, dbt tests) as a configuration change, not a rebuild.

- **Keep a native fallback.** PDC's own profiling already computes basic quality stats (completeness, uniqueness, validity, density). It's coarser than PDQ, but it's a DQ signal that survives a DQLabs exit — wire it as the fallback.

- **Own your rules.** Keep DQ rule definitions in the registry / source control where they're portable, not trapped in the vendor's engine.

- **Treat Trust Score as a consumed signal, not a source of truth.** Compute and store your own composite so you can reproduce it regardless of which DQ engine is underneath.

The classification and sensitivity pillars are already app-owned, so a DQLabs exit doesn't touch them — that's the whole point of the layer on top. Extend the same independence to the DQ pillar and the OEM relationship stops being a single point of failure.

## **Recommended architecture (the layer on top)**

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>┌─────────────────────────────┐</p>
<p>│ Classification Registry │ ← single source of truth</p>
<p>│ concept → term ID · tags · │ (governed, allow-listed)</p>
<p>│ sensitivity floor │</p>
<p>└──────────────┬──────────────┘</p>
<p>│ generate</p>
<p>┌──────────────┼──────────────┐</p>
<p>▼ ▼ ▼</p>
<p>Glossary terms DI methods Custom policies</p>
<p>(1 per table) (dict+pattern) (method combos)</p>
<p>│ │ │</p>
<p>└──────────────┼──────────────┘</p>
<p>▼ deploy via API (idempotent upsert)</p>
<p>┌───────────┐</p>
<p>│ PDC │</p>
<p>└─────┬─────┘</p>
<p>drift linter │ reconcile (UNKNOWN/UNLINKED/DRIFT/MISSING)</p>
<p>▼</p>
<p>Curated read-only Insights</p>
<p>(trust · sensitivity · ownership · lineage · relationships)</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Rules-first classification with an LLM residual sits inside the registry generation step. PDC becomes the deployment and execution target; governance lives above it.

## **Viability for Version 11**

Short answer: **yes — this critique is broadly viable for PDC 11.0.** The 11.0 GA release is mostly infrastructure and feature breadth (FerretDB replacing MongoDB, private PostgreSQL schemas, Databricks Unity Catalog, lineage graph projection, entity-usage tracking, data-product enhancements, workflow-approval notifications) plus a UI-Kit styling refresh. The *structural governance* gaps this document identifies are largely untouched.

Two clarifications matter before the table:

- The "completely revamped UX" headline in the 11.0 platform notes refers to the **Pentaho User Console (PUC)** used by PDI/PBA users — **not** PDC. PDC's own 11.0 UX change is a UI-Kit alignment for visual consistency, not a workflow redesign.

- Several gaps are *partially mitigated* in 11.0 (glossary approval workflows, expanded public APIs, RBAC-tailored views). Treat those as "still needs the layer on top," not "solved."

| **\#** | **Gap**                                    | **11.0 status**      | **Note**                                                                                                                                              |
|--------|--------------------------------------------|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| **1**  | Bulk data-source loader                    | **Persists**         | Connection import/export and PDI-triggered auto-create exist; no true bulk loader                                                                     |
| **2**  | JDBC driver auto-provisioning              | **Persists**         | Not addressed                                                                                                                                         |
| **3**  | Ingest metrics shown to analysts           | **Partial**          | RBAC + tailored role views + stat pre-aggregation help; curation still the implementer's job                                                          |
| **4**  | Freeform glossary drift                    | **Partial**          | 11.0 adds approval workflows, templates, mandatory comments, audit — gates drift, doesn't remove it; no single source of truth                        |
| **5**  | Registry syncing glossary ↔ classification | **Persists**         | Not a native concept                                                                                                                                  |
| **6**  | Native dictionaries/patterns as-is         | **Persists**         | Same freeform model; ML/GenAI document classification added but tag surface unchanged. The custom-set *how-to* is now solved: the 11.0 import contract is live-validated end-to-end                          |
| **7**  | No real policy objects                     | **Persists**         | Data Identification policy is still an ad-hoc method combination                                                                                      |
| **8**  | Tags vs terms not enforced                 | **Persists**         | No consistency enforcement                                                                                                                            |
| **9**  | Trust Score on columns/folders             | **Mostly persists**  | Folder-level *stat* aggregation added (not trust score); API compute helps you derive it                                                              |
| **10** | API-driven visualization                   | **Improving**        | More public APIs + built-in Entity Usage dashboards; your read-only app approach still valid                                                          |
| **11** | Automate via API                           | **Improving**        | Expanded public APIs (data-pipe registration, usage ingestion) — plus a live-confirmed GraphQL surface at `{pdc}/graphql` (full method CRUD) sharing the REST API's Keycloak bearer                          |
| **12** | LLM used surgically                        | **Design principle** | 11.0 leans *further* into LLM/GenAI — makes "keep it residual" more important, not less                                                               |
| **13** | UX redesign                                | **Cosmetic only**    | UI-Kit alignment ≠ workflow redesign; the logical-workflow critique stands — live proof: no Delete for identification methods, and the Edit form drops rule conditions                                       |
| **14** | Config-as-code / promotion                 | **Persists**         | Import/export remains opaque bundles                                                                                                                  |
| **15** | Classification explainability              | **Partial**          | Activity logging + OTEL observability exist; per-decision provenance still yours to emit                                                              |
| **16** | Bulk remediation / validation              | **Persists**         | No native bulk remediation or pre-deploy dry-run; the layer-on-top reconcile (term-id verify at scale) and scoped bulk retire now exist and ran against live 11.0                                            |
| **17** | Custom properties governance               | **Partial**          | 11.0 consolidated property *management* and offers some enumerated values; freeform drift + no registry link persist                                  |
| **18** | Metadata rules guardrails                  | **Partial**          | 11.0 improves rule *authoring* (classification → objects → attributes); no impact preview, precedence, or registry-sourced values                     |
| **19** | Galaxy relationship querying               | **Persists**         | 11.0 surfaces more edges (ML/manual lineage) in Galaxy but adds no relationship-query engine; node-limit cap and missing ownership pivot remain       |
| **20** | Lineage coverage & impact export           | **Improving**        | 11.0 adds graph projection, design-time/manual/ML lineage, hierarchical layout; coverage metric, impact-set export, and staleness signal still absent |
| **21** | Unstructured discovery LLM dependency      | **Persists**         | 11.0 keeps the same model design; default doc-classification model narrow and English-only; a custom LLM is still required for real coverage          |
| **22** | Similarity is post-hoc, not pre-entry      | **Persists**         | Metadata Similarity remains a batch suggestion job reviewed after assets/terms exist; no pre-commit check                                             |

**Bottom line.** Of 22 gaps, roughly 13 persist unchanged in 11.0, 6 are partially mitigated, and 3 (API breadth and lineage) are actively improving in a direction that *supports* the recommended layer-on-top approach rather than replacing it. The core thesis — PDC is the execution engine, governance belongs in a registry-driven layer above it — is as true in 11.0 as in 10.2.11. When re-pointing the courseware at 11.0, reframe the partially-mitigated gaps (3, 4, 10, 11, 15, 17, 18) and the improving ones (10, 11, 20) as "here's what's better, here's what still needs owning," and keep the rest as-is.

### Live-validated on 11.0 (hands-on, 2026-07)

The layer-on-top architecture is no longer only an AWC-era argument — its core loop has now run end-to-end against a live PDC 11.0.0 build in the CSCU training scenario ([PDC-Scenarios](https://github.com/jporeilly/PDC-Scenarios), exercising the [Glossary](https://github.com/jporeilly/PDC-Glossary-Generator) and [Policy](https://github.com/jporeilly/PDC-Policy-Generator) Generators): registry generated from scan evidence → glossary imported → identification methods **authored from the registry and imported** (custom-only, governed tags, term bindings) → identification run → **term ids reconciled at full-registry scale** → obsolete method set **retired in bulk**. Two discovery methods made that possible and are worth institutionalizing: the import contract was learned by **exporting a built-in method and mirroring PDC's own Export format** (the documentation's shapes were wrong on every detail that mattered), and the GraphQL surface behind the UI was mapped **through Apollo's validation-error suggestions** despite introspection being disabled. The general lesson: on this product, live behaviour is the specification — sample the running build before building against the docs.

## **Prioritization**

Priority is set by impact-at-scale, whether the item is a foundational enabler, and effort — updated (2026-07) with what the live 11.0 build has already proven, which collapses the cost of several items. The single most important sequencing rule is unchanged: **do the Classification Registry (gap 5) first** — it unblocks roughly a third of the list, and little else compounds without it. Two deliberate re-rankings: **config-as-code (14) rises to P1** because uuid5-keyed upserts are now live-proven and promotion is close to free once methods are generated; **JDBC auto-provisioning (2) drops to P3** — driver staging is a one-time, per-source-type setup cost, not a scale blocker, and it shouldn't sit on the critical path. Tiers: **P0** foundational, **P1** high-impact once P0 lands, **P2** governance depth, **P3** long-horizon, low-urgency, or largely Pentaho's to fix.

| **Priority** | **Item (gaps)**                                              | **Rationale**                                                                                                             | **Depends on**      |
|--------------|--------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|---------------------|
| **P0**       | Classification Registry (5)                                  | The single source of truth; unblocks 4, 6, 7, 8, 14, 17, 18. Nothing else compounds without it.                           | —                   |
| **P0**       | Bulk data-source loader (1)                                  | Biggest onboarding cost at 100+ sources; self-contained; immediate ROI.                                                   | API access          |
| **P0**       | Adopt the LLM guardrail (12)                                 | Zero-build policy: rules-first, ordinal floor, LLM residual-only. Adopt before any classification runs.                   | —                   |
| **P1**       | Custom two-tier dictionaries/patterns (6)                    | Classification quality; replaces the drift-prone native set. **De-risked: the 11.0 import contract is live-validated.**   | 5                   |
| **P1**       | Generate policies + enforce tag/term identity (7, 8)         | Near-free once the registry generates both sides; custom-only run policy proven live.                                     | 5                   |
| **P1**       | Config-as-code / promotion (14)                              | **Promoted from P2:** uuid5 upserts live-proven — the registry versioned in git deploys idempotently per environment.     | 5, 11               |
| **P1**       | Pre-entry term dedup gate (22)                               | Catch duplicate terms at creation; PDC's Metadata Similarity is post-hoc cleanup only.                                    | 5                   |
| **P1**       | Role-scoped Insights: analyst views + API dashboards (3, 10) | High-visibility; this is what stakeholders actually see.                                                                  | 11                  |
| **P1**       | API automation: authoring, reconcile, drift-lint (11, 16)    | Cross-cutting; makes everything repeatable. **De-risked: authoring, reconcile, and bulk retire already run live.**        | 5                   |
| **P2**       | Custom properties governance (17)                            | Closes the third drift surface with pick-lists + required-property coverage.                                              | 5                   |
| **P2**       | Abstract the DQ source (DQLabs OEM risk)                     | Keep DQ swappable — native-profiling fallback + portable rules — so a discontinued OEM is a config change, not a rebuild. | 11                  |
| **P2**       | Metadata rules guardrails (18)                               | Closes the fourth drift surface; needs impact preview + precedence.                                                       | 5, 11               |
| **P2**       | Classification explainability (15)                           | Provenance in the envelope so stewards can defend and debug decisions; seed provenance already in the registry.           | 11                  |
| **P2**       | Trust Score rollups (9)                                      | Derive column/folder scores from the input signals (native score isn't in the public API).                                | 11                  |
| **P2**       | Relationship queries in Insights (19)                        | Ownership/path lenses Galaxy can't answer.                                                                                | 11                  |
| **P2**       | Plan for the unstructured LLM (21)                           | Configure/host a local LLM; English-only, narrow default; feed terms from the registry.                                   | 12                  |
| **P3**       | JDBC driver auto-provisioning (2)                            | **Demoted from P0:** one-time per-source-type staging toil, not a show-stopper; fold into the bulk loader when convenient. | 1                   |
| **P3**       | Lineage coverage + impact intelligence (20)                  | Incremental: push OpenLineage from non-emitting tools, then coverage % + impact sets.                                     | 11, source emitters |
| **P3**       | UX redesign (13)                                             | Largest effort and largely Pentaho's to deliver; mitigate now via the API-driven apps.                                    | —                   |

**Standing guardrails** (apply throughout, not a phase):

- Sensitivity floor is ordinal; rules only raise, never lower.

- LLM handles residual only; never authoritative.

- Every deploy is idempotent and drift-linted.

## **What this means for courseware / customers**

The through-line to teach is simple: **PDC is the execution engine, not the governance system.** Scale and consistency come from a registry-driven, API-automated layer on top, with LLMs kept to residual work. Teaching the manual UI paths as the "real" workflow sets customers up for exactly the drift this document catalogues. The courseware that teaches the governed workflow instead — per-vertical workshops for both generators — lives in [PDC-Scenarios](https://github.com/jporeilly/PDC-Scenarios).
