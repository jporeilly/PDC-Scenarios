#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PDC-Demo — the ONE bootstrap
#
# Stands up (or updates) the complete ~/PDC-Demo lab checkout:
#   - the Glossary Generator (the PDC-Demo checkout itself)
#   - the Policy Generator   (sparse: the app only)
#   - PDC-Scenarios          (sparse: ONLY the selected vertical — its data
#                             kit, domain pack and courseware + the shared lab)
# Re-runs update all three; the selected vertical is remembered (pass an ID
# to select or switch). Then `make scenario ID=<ID>` inside PDC-Scenarios
# loads the data sources.
#
#   curl -fsSL https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.sh | bash -s -- CSCU
#
#   ./install-pdc-demo.sh                      # update everything (~/PDC-Demo)
#   ./install-pdc-demo.sh CSCU                 # select/switch the vertical
#   ./install-pdc-demo.sh /path/to/PDC-Demo RETAIL
#   PDC_DEMO_DIR=/srv/PDC-Demo ./install-pdc-demo.sh
#
# The app repos carry their own install-pdc-demo.sh for single-app updates;
# this script is the one-command whole-lab entry point.
# ---------------------------------------------------------------------------
set -euo pipefail

GLOSS_URL="${GLOSSARY_REPO_URL:-https://github.com/jporeilly/PDC-Glossary-Generator.git}"
POLICY_URL="${POLICY_REPO_URL:-https://github.com/jporeilly/PDC-Policy-Generator.git}"
SCEN_URL="${SCENARIOS_REPO_URL:-https://github.com/jporeilly/PDC-Scenarios.git}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RS=$'\033[0m'
  TEAL=$'\033[38;5;37m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
else
  B=""; DIM=""; RS=""; TEAL=""; GREEN=""; YELLOW=""; RED=""
fi
ok(){   printf "  ${GREEN}✓${RS} %s\n" "$1"; }
warn(){ printf "  ${YELLOW}!${RS} %s\n" "$1"; }
die(){  printf "  ${RED}✗ %s${RS}\n" "$1" >&2; exit 1; }

DEMO="${PDC_DEMO_DIR:-$HOME/PDC-Demo}"
VERTICAL="${VERTICAL:-}"
for arg in "$@"; do
  if [ -d "$arg" ] || [ "${arg#/}" != "$arg" ] || [ "${arg#~}" != "$arg" ]; then DEMO="$arg"
  else VERTICAL="$(printf '%s' "$arg" | tr '[:lower:]' '[:upper:]')"
  fi
done

printf "\n${TEAL}${B}  PDC-Demo — one-command lab install/update${RS}\n"
printf "${DIM}  Glossary Generator + Policy Generator + the selected vertical.${RS}\n\n"

printf "${B}  Pre-flight${RS}\n"
command -v git >/dev/null 2>&1 || die "git is not installed."
ok "git $(git --version | awk '{print $3}')"
echo

# --- 1. the PDC-Demo checkout (Glossary Generator) ---------------------------
printf "${B}  1/3  Glossary Generator (the PDC-Demo checkout)${RS}\n"
if [ -d "$DEMO/.git" ]; then
  [ -d "$DEMO/glossary_generator" ] || die "$DEMO is a git checkout but not the Glossary repo"
  git -C "$DEMO" pull -q --ff-only || die "pull failed — local changes in $DEMO? Commit/stash and re-run."
  ok "Updated to $(git -C "$DEMO" rev-parse --short HEAD)"
elif [ -e "$DEMO" ] && [ -n "$(ls -A "$DEMO" 2>/dev/null)" ]; then
  die "$DEMO exists but is not a git checkout — move it aside and re-run."
else
  printf "  ${DIM}cloning…${RS}\n"
  git clone -q "$GLOSS_URL" "$DEMO"
  ok "Cloned to $DEMO"
fi
ok "Glossary app $(cat "$DEMO/glossary_generator/VERSION" 2>/dev/null | tr -d '[:space:]')"
echo

# --- 2. the Policy Generator (sparse: app only) -------------------------------
printf "${B}  2/3  Policy Generator${RS}\n"
PT="$DEMO/PDC-Policy-Generator"
if [ -d "$PT/.git" ]; then
  git -C "$PT" pull -q --ff-only || warn "Policy pull failed (local changes?)"
  ok "Updated to $(git -C "$PT" rev-parse --short HEAD)"
else
  printf "  ${DIM}cloning (sparse, app only)…${RS}\n"
  git -C "$DEMO" clone -q --filter=blob:none --sparse "$POLICY_URL" PDC-Policy-Generator
  git -C "$PT" sparse-checkout set policy_generator
  ok "Cloned (policy_generator/ only)"
fi
ok "Policy app $(cat "$PT/policy_generator/VERSION" 2>/dev/null | tr -d '[:space:]')"
echo

# --- 3. PDC-Scenarios (sparse: the selected vertical) -------------------------
printf "${B}  3/3  PDC-Scenarios (the vertical)${RS}\n"
ST="$DEMO/PDC-Scenarios"
if [ ! -d "$ST/.git" ] && [ -n "$VERTICAL" ]; then
  printf "  ${DIM}cloning (sparse, %s only)…${RS}\n" "$VERTICAL"
  git -C "$DEMO" clone -q --filter=blob:none --no-checkout "$SCEN_URL" PDC-Scenarios
  git -C "$ST" sparse-checkout set "data_sources/lab" "data_sources/$VERTICAL" "courseware/$VERTICAL" "diagrams"
  git -C "$ST" checkout -q
fi
if [ -d "$ST/.git" ]; then
  git -C "$ST" pull -q --ff-only >/dev/null 2>&1 || warn "PDC-Scenarios pull failed (local changes?)"
  CUR="$(git -C "$ST" sparse-checkout list 2>/dev/null | sed -n 's#^data_sources/##p' | grep -v '^lab$' | head -1 || true)"
  [ -n "$VERTICAL" ] || VERTICAL="$CUR"
  if [ -n "$VERTICAL" ]; then
    if (cd "$ST" && bash select-vertical.sh "$VERTICAL" >/dev/null); then
      ok "Vertical $VERTICAL — data kit + domain pack + courseware"
    else
      warn "select-vertical.sh $VERTICAL failed — valid ids: CSCU RETAIL HEALTH MFG"
    fi
  else
    warn "No vertical selected — re-run with one: install-pdc-demo.sh CSCU"
  fi
  # migrate a lab .env stranded in the pre-carve-out location
  if [ -f "$DEMO/data_sources/lab/.env" ] && [ -d "$ST/data_sources/lab" ] \
     && [ ! -f "$ST/data_sources/lab/.env" ]; then
    cp "$DEMO/data_sources/lab/.env" "$ST/data_sources/lab/.env"
    ok "Migrated lab .env from the old in-repo location"
  fi
else
  warn "Skipped — pass a vertical to set it up: install-pdc-demo.sh CSCU"
fi
# keep the outer checkout's git status clean
for d in PDC-Policy-Generator PDC-Scenarios; do
  if [ -d "$DEMO/$d" ] && ! grep -qx "$d/" "$DEMO/.git/info/exclude" 2>/dev/null; then
    echo "$d/" >> "$DEMO/.git/info/exclude"
  fi
done
echo

printf "${B}  Next${RS}\n"
if [ -n "$VERTICAL" ]; then
  printf "  ${TEAL}cd $ST && make scenario ID=$VERTICAL${RS}   ${DIM}(lab up + data sources loaded)${RS}\n"
  printf "  ${DIM}apps:  glossary → $DEMO/glossary_generator (./run.sh, :5000)\n"
  printf "         policy   → $PT/policy_generator (bash run.sh --host 0.0.0.0, :5001)${RS}\n\n"
else
  printf "  ${TEAL}install-pdc-demo.sh CSCU${RS}   ${DIM}(pick a vertical first)${RS}\n\n"
fi
