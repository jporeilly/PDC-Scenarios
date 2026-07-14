#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PDC-Scenarios — vertical selector
#
# Clone this repo SPARSE and pull only the vertical you deliver: the shared
# lab plus that scenario's data kit, domain pack and courseware. Run again
# with a different ID to switch (or add) verticals; run with --all for
# everything.
#
#   First time (nothing local yet):
#     git clone --filter=blob:none --no-checkout https://github.com/jporeilly/PDC-Scenarios.git
#     cd PDC-Scenarios && ./select-vertical.sh CSCU     # via: git checkout main -- select-vertical.sh
#
#   Or from a checkout:   ./select-vertical.sh CSCU | RETAIL | HEALTH | MFG | --all
#
# After selecting: ./install-scenario.sh <ID> installs the domain pack +
# roster into the Glossary app, and data_sources/lab stands up the sources.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

[ $# -ge 1 ] || { echo "usage: $0 <SCENARIO-ID>|--all   (e.g. $0 CSCU)"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git checkout of PDC-Scenarios"; exit 1; }

if [ "$1" = "--all" ]; then
  git sparse-checkout disable
  echo "sparse checkout disabled — full repo checked out"
  exit 0
fi

ID="$1"
# root files (README, installers, this script) always stay; add the shared
# lab, the vertical's data kit, and its courseware (all apps' sets)
git sparse-checkout set "data_sources/lab" "data_sources/$ID" "courseware/$ID" "diagrams"
[ -d "data_sources/$ID" ] || { echo "unknown vertical '$ID' — no data_sources/$ID on this branch"; git sparse-checkout list; exit 1; }
echo ""
echo "Vertical: $ID"
git sparse-checkout list | sed 's/^/  /'
if [ -z "${PDC_SCEN_QUIET:-}" ]; then
  echo ""
  echo "Next:"
  echo "  1. Sources:    make scenario ID=$ID   (lab up + data loaded; safe to re-run)"
  echo "  2. Glossary:   make pack ID=$ID       (domain pack + roster into the app)"
  echo "  3. Courseware: courseware/$ID/"
fi
