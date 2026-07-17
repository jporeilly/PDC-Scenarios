# Changelog

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
