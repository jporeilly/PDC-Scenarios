#!/usr/bin/env bash
# ============================================================
#  PDC-Scenarios — load a scenario's cast into PDC's Keycloak
#
#  Creates the scenario's users in the `pdc` realm and maps each to the
#  PDC roles the roster names — so the whole cast can log in and the RBAC
#  workshops work without hand-creating users in the Keycloak console.
#
#  Runs ON THE LAB VM (needs docker + the pdc-um-keycloak-1 container).
#  Idempotent: existing users are kept (password + roles re-applied).
#
#  Usage:
#    ./load-pdc-users.sh CSCU                    # one scenario's cast (roster passwords)
#    ./load-pdc-users.sh ALL                     # all 36 users, every vertical
#    ./load-pdc-users.sh CSCU --password 'S3cret!'   # override every password
#    ./load-pdc-users.sh CSCU --dry-run          # show the plan, change nothing
#    ./load-pdc-users.sh CSCU --fix-policy       # relax the realm password policy
#                                                #   to length(8) first (LAB ONLY —
#                                                #   policies like specialChars(1)
#                                                #   reject the training passwords)
#    ./load-pdc-users.sh --list-roles            # dump the realm's roles + groups
#
#  Roster: courseware/PDC-Users-All-Scenarios.csv when present (explicit
#  Username + per-user Lab_Password; kept even in a sparse checkout — cone
#  mode retains top-level courseware/ files); falls back to the scenario's
#  Workshop-00 users.csv.
#
#  Role mapping: roster display names ("Data Steward") are normalized to
#  snake_case and matched against the realm's ACTUAL roles; if no realm
#  role matches, a same-named GROUP is tried; anything still unmatched is
#  reported loudly (run --list-roles and extend ROLE_ALIASES below).
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

KC_CONTAINER="${KC_CONTAINER:-}"
KC_PATH="/opt/keycloak/bin/kcadm.sh"
REALM="pdc"

SCENARIO=""; PASSWORD=""; DRY=0; LIST_ROLES=0; FIX_POLICY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --password) PASSWORD="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --list-roles) LIST_ROLES=1; shift ;;
    --fix-policy) FIX_POLICY=1; shift ;;
    *) SCENARIO="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; shift ;;
  esac
done

# training lab defaults (fictional scenarios; never production values)
default_password() {
  case "$1" in
    CSCU) echo copperstate ;;  RETAIL) echo canyontrail ;;
    HEALTH) echo lakeshore ;;  MFG) echo cascade ;;
    *) echo "" ;;
  esac
}

# roster display-name -> realm role, when snake_casing alone isn't enough.
# Left side is the normalized roster name, right side the realm role to try.
ROLE_ALIASES="
catalog_admin=admin
administrator=admin
system_administrator=admin
"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }
die(){  printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker not found — run this on the lab VM."
if [ -z "$KC_CONTAINER" ]; then
  KC_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E 'um-keycloak' | head -1 || true)"
fi
[ -n "$KC_CONTAINER" ] || die "Keycloak container not found (expected pdc-um-keycloak-1). Is PDC up?"

# kcadm wrapper: logs in per call using the container's own master-admin env;
# the server runs under the /keycloak relative path (plain :8080 404s).
kc() {
  docker exec "$KC_CONTAINER" sh -c "
    $KC_PATH config credentials --server http://localhost:8080/keycloak \
      --realm master --user \"\$KEYCLOAK_ADMIN\" --password \"\$KEYCLOAK_ADMIN_PASSWORD\" >/dev/null 2>&1 \
    && $KC_PATH $*"
}

if [ "$LIST_ROLES" -eq 1 ]; then
  echo "Realm '$REALM' roles:";  kc "get roles -r $REALM --fields name" | grep '"name"' || true
  echo "Realm '$REALM' groups:"; kc "get groups -r $REALM --fields name" | grep '"name"' || true
  exit 0
fi

[ -n "$SCENARIO" ] || die "Pass a scenario id (CSCU/RETAIL/HEALTH/MFG), ALL, or --list-roles."
# Preferred roster: the consolidated CSV (explicit Username + per-user
# Lab_Password, all four verticals). Fallback: the Workshop-00 roster.
CONS="courseware/PDC-Users-All-Scenarios.csv"
CSV=""
if [ -f "$CONS" ]; then
  CSV="$CONS"
elif [ "$SCENARIO" != "ALL" ]; then
  CSV="courseware/$SCENARIO/Platform/Workshop-00-Preflight/assets/users.csv"
  [ -f "$CSV" ] || die "Roster not found: $CONS or $CSV (is the $SCENARIO vertical checked out?)"
else
  die "ALL needs the consolidated roster: $CONS"
fi
DEFPASS="$(default_password "$SCENARIO")"

command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python

echo
echo "  Loading $SCENARIO cast into Keycloak realm '$REALM' ($KC_CONTAINER)"
echo "  Roster: $CSV"
echo

# the realm's password policy: lab rosters use simple training passwords
# (copperstate etc), which realm policies like specialChars(1) reject.
# --fix-policy relaxes the LAB realm's policy to length(8), loudly.
POLICY="$(kc "get realms/$REALM --fields passwordPolicy" | sed -n 's/.*"passwordPolicy" : "\(.*\)".*/\1/p')"
if [ -n "$POLICY" ]; then
  if [ "$FIX_POLICY" -eq 1 ]; then
    warn "relaxing realm password policy (was: $POLICY -> length(8)) — training lab only"
    kc "update realms/$REALM -s 'passwordPolicy=length(8)'" >/dev/null \
      && ok "password policy relaxed" || warn "policy update failed — set it in the Keycloak console"
  else
    warn "realm password policy is '$POLICY' — simple lab passwords may be rejected; re-run with --fix-policy to relax it (lab only)"
  fi
fi

# the realm's actual roles + groups, once (names only, one per line)
REALM_ROLES="$(kc "get roles -r $REALM --fields name" | sed -n 's/.*"name" : "\(.*\)".*/\1/p')"
REALM_GROUPS="$(kc "get groups -r $REALM --fields name,id")"

resolve_role() {  # display name -> the realm's ACTUAL role name (or empty)
  # case-insensitive: the realm capitalizes (Data_Steward), rosters don't
  local norm alias cand actual
  norm="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/_/g;s/^_//;s/_$//')"
  alias="$(printf '%s\n' "$ROLE_ALIASES" | sed -n "s/^${norm}=//p" | head -1)"
  for cand in "$norm" "$alias"; do
    [ -n "$cand" ] || continue
    actual="$(printf '%s\n' "$REALM_ROLES" | grep -ix "$(printf '%s' "$cand" | sed 's/[^a-z0-9_]//g')" | head -1)"
    [ -n "$actual" ] && { echo "$actual"; return 0; }
  done
  return 1
}

# CSV -> TAB rows: username, email, first, last, roles(;-joined), password.
# Handles BOTH shapes: the consolidated roster (Username/Lab_Password,
# filtered by scenario) and a Workshop-00 roster (First/Last, username
# derived from the email). Quoted commas -> real CSV parsing, no awk.
"$PY" - "$CSV" "$SCENARIO" <<'ROSTER' | while IFS="$(printf '\t')" read -r U EMAIL FIRST LAST ROLES PW; do
import csv, sys
path, scen = sys.argv[1], sys.argv[2]
with open(path, newline="", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        email = (row.get("Email") or "").strip()
        if not email:
            continue
        if "Scenario" in row and scen != "ALL" and (row.get("Scenario") or "").strip().upper() != scen:
            continue
        user = (row.get("Username") or "").strip().lower() or email.split("@")[0].lower()
        first = (row.get("First_Name") or "").strip() or user.split(".")[0].title()
        last = (row.get("Last_Name") or "").strip() or (user.split(".")[1].title() if "." in user else "")
        print("\t".join([user, email, first, last,
                         (row.get("PDC_Roles") or "").strip(),
                         (row.get("Lab_Password") or "").strip()]))
ROSTER
  printf '\033[1m  %s\033[0m  (%s)\n' "$U" "$ROLES"
  if [ "$DRY" -eq 1 ]; then continue; fi

  # create-or-keep the user (emailVerified so the direct grant works at once)
  UID_JSON="$(kc "get users -r $REALM -q username=$U --fields id" || true)"
  if printf '%s' "$UID_JSON" | grep -q '"id"'; then
    ok "exists — keeping (password + roles re-applied)"
  else
    kc "create users -r $REALM -s username=$U -s email=$EMAIL \
        -s firstName='$FIRST' -s lastName='$LAST' \
        -s enabled=true -s emailVerified=true" >/dev/null \
      && ok "created" || { warn "create failed — skipping"; continue; }
  fi

  # precedence: --password override > the roster row's Lab_Password > scenario default
  ROWPASS="${PASSWORD:-${PW:-$DEFPASS}}"
  if [ -n "$ROWPASS" ]; then
    kc "set-password -r $REALM --username $U --new-password '$ROWPASS'" >/dev/null \
      && ok "password set" || warn "set-password failed (realm password policy? re-run with --fix-policy)"
  else
    warn "no password for $U (no --password, roster blank, no scenario default) — skipped"
  fi

  # map each roster role -> realm role (fallback: same-named group).
  # printf '%s\n': without the trailing newline, `read` drops the LAST role —
  # single-role users got no role at all.
  printf '%s\n' "$ROLES" | tr ';' '\n' | sed 's/^ *//;s/ *$//' | while read -r R; do
    [ -n "$R" ] || continue
    if ROLE="$(resolve_role "$R")"; then
      kc "add-roles -r $REALM --uusername $U --rolename $ROLE" >/dev/null \
        && ok "role: $R -> $ROLE" || warn "role assign failed: $ROLE"
    else
      GNORM="$(printf '%s' "$R" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/_/g')"
      GID="$(printf '%s' "$REALM_GROUPS" | "$PY" -c "
import sys, json, re
want = sys.argv[1]
norm = lambda s: re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')
try: gs = json.load(sys.stdin)
except Exception: gs = []
print(next((g['id'] for g in gs if norm(g.get('name','')) == want), ''))
" "$GNORM")"
      if [ -n "$GID" ]; then
        UID2="$(kc "get users -r $REALM -q username=$U --fields id" | sed -n 's/.*"id" : "\(.*\)".*/\1/p' | head -1)"
        kc "update users/$UID2/groups/$GID -r $REALM -n" >/dev/null \
          && ok "group: $R" || warn "group join failed: $R"
      else
        warn "NO realm role or group matches '$R' — run: $0 --list-roles  (then extend ROLE_ALIASES)"
      fi
    fi
  done
done

echo
ok "Done. Verify a login:  curl -sk -X POST 'https://pentaho.io/keycloak/realms/pdc/protocol/openid-connect/token' -d client_id=pdc-client -d grant_type=password -d username=<user> -d password='<pass>'"
