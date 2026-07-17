#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PDC-Demo — the ONE bootstrap
#
# Stands up (or updates) the complete ~/PDC-Demo lab checkout:
#   - the Glossary Generator (the PDC-Demo checkout itself)          :5000
#   - the Policy Generator   (sparse: app + frontend)                :5001
#   - Catalog Insights       (PDC-Insights, full clone)              :5002
#   - PDC-Scenarios          (sparse: ONLY the selected vertical — its data
#                             kit, domain pack and courseware + the shared lab)
# Re-runs update all four; the selected vertical is remembered (pass an ID
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
INSIGHTS_URL="${INSIGHTS_REPO_URL:-https://github.com/jporeilly/PDC-Insights.git}"
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

# build_ui LABEL FRONTEND_DIR CHANGED — build an app's React UI (frontend/dist)
# when it is missing or the checkout just moved. All three apps serve dist.
build_ui(){
  local label="$1" fe="$2" changed="$3"
  [ -f "$fe/package.json" ] || return 0
  if [ -f "$fe/dist/index.html" ] && [ "$changed" != "1" ]; then
    ok "$label web UI up to date (frontend/dist)"; return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    warn "npm not found — $label falls back to its legacy UI / API docs until frontend/ is built (Node 18+)"; return 0
  fi
  printf "  ${DIM}building the %s web UI (npm install + build)…${RS}\n" "$label"
  if (cd "$fe" && npm install --no-fund --no-audit --loglevel=error >/dev/null 2>&1 \
      && npm run build --loglevel=error >/dev/null 2>&1); then
    ok "$label web UI built (frontend/dist)"
  else
    warn "$label UI build failed — run: cd $fe && npm install && npm run build"
  fi
}

DEMO="${PDC_DEMO_DIR:-$HOME/PDC-Demo}"
VERTICAL="${VERTICAL:-}"
for arg in "$@"; do
  if [ -d "$arg" ] || [ "${arg#/}" != "$arg" ] || [ "${arg#~}" != "$arg" ]; then DEMO="$arg"
  else VERTICAL="$(printf '%s' "$arg" | tr '[:lower:]' '[:upper:]')"
  fi
done

printf "\n${TEAL}${B}  PDC-Demo — one-command lab install/update${RS}\n"
printf "${DIM}  Glossary + Policy + Insights apps + the selected vertical.${RS}\n\n"

printf "${B}  Pre-flight${RS}\n"
command -v git >/dev/null 2>&1 || die "git is not installed."
ok "git $(git --version | awk '{print $3}')"
echo

# --- 1. the PDC-Demo checkout (Glossary Generator) ---------------------------
printf "${B}  1/4  Glossary Generator (the PDC-Demo checkout)${RS}\n"
GLOSS_CHANGED=1
if [ -d "$DEMO/.git" ]; then
  [ -d "$DEMO/glossary_generator" ] || die "$DEMO is a git checkout but not the Glossary repo"
  GB="$(git -C "$DEMO" rev-parse HEAD)"
  git -C "$DEMO" pull -q --ff-only || die "pull failed — local changes in $DEMO? Commit/stash and re-run."
  ok "Updated to $(git -C "$DEMO" rev-parse --short HEAD)"
  [ "$GB" != "$(git -C "$DEMO" rev-parse HEAD)" ] || GLOSS_CHANGED=0
elif [ -e "$DEMO" ] && [ -n "$(ls -A "$DEMO" 2>/dev/null)" ]; then
  die "$DEMO exists but is not a git checkout — move it aside and re-run."
else
  printf "  ${DIM}cloning…${RS}\n"
  git clone -q "$GLOSS_URL" "$DEMO"
  ok "Cloned to $DEMO"
fi
build_ui "Glossary" "$DEMO/frontend" "$GLOSS_CHANGED"
ok "Glossary app $(cat "$DEMO/glossary_generator/VERSION" 2>/dev/null | tr -d '[:space:]')"
echo

# --- 2. the Policy Generator (hidden sparse clone, linked flat) ---------------
printf "${B}  2/4  Policy Generator${RS}\n"
PT="$DEMO/.pdc-policy-generator"
# migrate the old visible layout
if [ -d "$DEMO/PDC-Policy-Generator/.git" ] && [ ! -d "$PT" ]; then
  mv "$DEMO/PDC-Policy-Generator" "$PT"
  ok "Migrated PDC-Policy-Generator/ -> .pdc-policy-generator/"
fi
POLICY_CHANGED=1
if [ -d "$PT/.git" ]; then
  PB="$(git -C "$PT" rev-parse HEAD)"
  git -C "$PT" sparse-checkout add frontend 2>/dev/null || true   # widen pre-1.7 checkouts (app only)
  git -C "$PT" pull -q --ff-only || warn "Policy pull failed (local changes?)"
  ok "Updated to $(git -C "$PT" rev-parse --short HEAD)"
  [ "$PB" != "$(git -C "$PT" rev-parse HEAD)" ] || POLICY_CHANGED=0
else
  printf "  ${DIM}cloning (sparse, app + frontend)…${RS}\n"
  git -C "$DEMO" clone -q --filter=blob:none --sparse "$POLICY_URL" .pdc-policy-generator
  git -C "$PT" sparse-checkout set policy_generator frontend
  ok "Cloned (app + frontend)"
fi
# build the React UI (1.7.0+ serves it from frontend/dist)
build_ui "Policy" "$PT/frontend" "$POLICY_CHANGED"
# flat view: policy_generator/ beside glossary_generator/, README kept separate
ln -sfn ".pdc-policy-generator/policy_generator" "$DEMO/policy_generator"
cp -f "$PT/README.md" "$DEMO/README-Policy.md" 2>/dev/null || true
ok "Policy app $(cat "$PT/policy_generator/VERSION" 2>/dev/null | tr -d '[:space:]') — linked at $DEMO/policy_generator"
echo

# --- 3. Catalog Insights (PDC-Insights, full clone) ---------------------------
printf "${B}  3/4  Catalog Insights (PDC-Insights)${RS}\n"
IT="$DEMO/PDC-Insights"
INS_CHANGED=1
if [ -d "$IT/.git" ]; then
  IB="$(git -C "$IT" rev-parse HEAD)"
  git -C "$IT" pull -q --ff-only || warn "Insights pull failed (local changes?)"
  ok "Updated to $(git -C "$IT" rev-parse --short HEAD)"
  [ "$IB" != "$(git -C "$IT" rev-parse HEAD)" ] || INS_CHANGED=0
else
  printf "  ${DIM}cloning…${RS}\n"
  git -C "$DEMO" clone -q "$INSIGHTS_URL" PDC-Insights
  ok "Cloned to $IT"
fi
build_ui "Insights" "$IT/frontend" "$INS_CHANGED"
# first-run config: point the app at the demo PDC (self-signed cert on the VM)
if [ ! -f "$IT/.env" ] && [ -f "$IT/.env.example" ]; then
  sed -e 's#^PDC_BASE_URL=.*#PDC_BASE_URL=https://pentaho.io#' \
      -e 's#^PDC_VERIFY_TLS=.*#PDC_VERIFY_TLS=false#' \
      "$IT/.env.example" > "$IT/.env"
  ok ".env created (PDC_BASE_URL=https://pentaho.io, TLS verify off) — review credentials before first run"
fi
ok "Insights app $(cat "$IT/VERSION" 2>/dev/null | tr -d '[:space:]')"
echo

# --- 4. PDC-Scenarios (sparse: the selected vertical) -------------------------
printf "${B}  4/4  PDC-Scenarios (the vertical)${RS}\n"
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
      # flat view: courseware/ at the top level beside the apps
      ln -sfn "PDC-Scenarios/courseware" "$DEMO/courseware"
      ok "Vertical $VERTICAL — data kit + domain pack + courseware (linked at $DEMO/courseware)"
      # first-time app config: install the pack/roster/datasources into the app.
      # Re-runs NEVER auto-reinstall — install-scenario resets the governed
      # dictionary, so refresh/switch is always an explicit act.
      APPDIR="$DEMO/glossary_generator"
      if [ ! -f "$APPDIR/domain_pack.json" ] && ! grep -qs '^GLOSSARY_DOMAIN_PACK=' "$APPDIR/.env"; then
        printf "  ${DIM}first-time app config — installing the %s scenario…${RS}\n" "$VERTICAL"
        if (cd "$ST" && GLOSSARY_APP_DIR="$APPDIR" bash install-scenario.sh "$VERTICAL" >/dev/null); then
          ok "Scenario installed into the Glossary app (pack, roster, datasources, company)"
        else
          warn "install-scenario.sh failed — run it manually: cd $ST && ./install-scenario.sh $VERTICAL"
        fi
      else
        ok "Glossary app already configured — refresh/switch explicitly: cd $ST && ./install-scenario.sh $VERTICAL"
      fi
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
  # Insights PDC login: the .env.example default (pdc_user) is the lab DATABASE
  # user, not a PDC login — seed the vertical's catalog.admin cast user instead.
  # Only touches the example default, so a hand-edited .env is left alone.
  ROSTER="$ST/courseware/PDC-Users-All-Scenarios.csv"
  if [ -n "$VERTICAL" ] && [ -f "$ROSTER" ] && [ -f "$IT/.env" ] \
     && grep -q '^PDC_USERNAME=pdc_user$' "$IT/.env"; then
    CAST="$(awk -F, -v v="$VERTICAL" '{gsub(/\r/,"")} $1==v && $3=="catalog.admin" {print $3","$7; exit}' "$ROSTER")"
    if [ -n "$CAST" ]; then
      sed -i -e "s#^PDC_USERNAME=.*#PDC_USERNAME=${CAST%%,*}#" \
             -e "s#^PDC_PASSWORD=.*#PDC_PASSWORD=${CAST##*,}#" "$IT/.env"
      ok "Insights .env → PDC login ${CAST%%,*} ($VERTICAL cast)"
    fi
  fi
else
  warn "Skipped — pass a vertical to set it up: install-pdc-demo.sh CSCU"
fi
# keep the outer checkout's git status clean (nested repos, links, extras)
for entry in ".pdc-policy-generator/" "PDC-Insights/" "PDC-Scenarios/" "policy_generator" "courseware" "README-Policy.md"; do
  grep -qx "$entry" "$DEMO/.git/info/exclude" 2>/dev/null || echo "$entry" >> "$DEMO/.git/info/exclude"
done
echo

printf "${B}  Next${RS}\n"
if [ -n "$VERTICAL" ]; then
  printf "  ${TEAL}cd %s && make scenario ID=%s${RS}   ${DIM}(lab up + data sources loaded)${RS}\n" "$ST" "$VERTICAL"
  printf "  ${DIM}users: cd %s && ./load-pdc-users.sh %s   (cast -> Keycloak + PDC roles)\n" "$ST" "$VERTICAL"
  printf "  apps:  glossary → %s/glossary_generator (./run.sh, :5000)\n" "$DEMO"
  printf "         policy   → %s/policy_generator (bash run.sh --host 0.0.0.0, :5001)\n" "$DEMO"
  printf "         insights → %s/PDC-Insights (./run.sh, :5002)${RS}\n\n" "$DEMO"
else
  printf "  ${TEAL}install-pdc-demo.sh CSCU${RS}   ${DIM}(pick a vertical first)${RS}\n\n"
fi
