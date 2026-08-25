# AWC — Arizona Water Company

The water-utility vertical, and the estate the 2026-08 **clean walkthrough**
ran against end to end (Glossary Generator 1.42.0 + Policy Generator 1.11.0,
PDC 11.0.0 at `https://pentaho.io`).

## Layout

| Path | What it is |
|---|---|
| `scenario.json` | Scenario metadata on the suite convention (see `../CSCU`) |
| `domain_pack/water_utility.example.json` | The domain pack the estate **taught**: learned abbreviations, curated seeds, governed vocabulary, category keywords, the adopted retention vocabulary (7y/10y) — `domain: water_utility`, `company: Arizona Water`. Install it in the Glossary Generator and the next scan of this company starts where the walkthrough finished. |
| `domain_pack/water_utility.people.json` | The steward roster (6 users, expertise set; matches the Keycloak cast loaded by `load-pdc-users.ps1`) |
| `deliverables/registry.…json` | The Classification Registry — 142 concepts, 45 seeded/authorable, 142/142 term ids resolved. The machine-readable term↔column contract the Policy Generator deploys from. |
| `deliverables/arizona-water-glossary-import.jsonl` | The import-ready glossary (1 glossary / 5 categories / 142 terms) — PDC Business Glossary → Import. Categories use "and", never "&" (PDC name search returns nothing for ampersand names). |
| `deliverables/dq-expectations.zip` | 128 data-quality expectations derived from the scan profile (format / allowed-values / completeness / uniqueness baselines) — for a DQ runner, not a PDC import. |
| `deliverables/governance_audit.json` | The steward audit trail behind the vocabulary — who approved, retired, folded and reset what, and when. |

## The state this snapshot represents

Deployed and proven on the live estate 2026-08-25:

- **45 methods** (17 patterns + 28 dictionaries) deployed id-bound; the four
  table-qualified Status vocabulary twins are deliberately **mapping-only**
  (same column name, same values — undetectable distinctly by construction;
  their term↔column links govern them).
- Single-token column hints are **anchored** (`(?i)(^status$)`) so a generic
  dictionary can never claim `account_status`.
- Read-back: **114 identified columns, zero multi-term** — every column
  carries exactly its own term. Drift 45/45 clean. Efficacy 41 live / 0 dead /
  4 honestly unresolvable (their only sources are nested JSON snapshot paths).

A colleague can rebuild this estate's governance from this folder alone:
install the pack, import the JSONL, load the Registry in the Policy
Generator, deploy.
