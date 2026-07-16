#!/usr/bin/env bash
# ============================================================
#  PDC-Scenarios — load a scenario's cast into PDC's Keycloak
#
#  Creates the scenario's users (from the Workshop-00 roster CSV) in the
#  `pdc` realm and maps each to the PDC roles the roster names — so the
#  whole cast can log in and the RBAC workshops work without hand-creating
#  users in the Keycloak console.
#
#  Runs ON THE LAB VM (needs docker + the pdc-um-keycloak-1 container).
#  Idempotent: existing users are kept (password + roles re-applied).
#
#  Usage:
#    ./load-pdc-users.sh CSCU                    # cast + roles, default lab password
#    ./load-pdc-users.sh CSCU --password 'S3cret!'
#    ./load-pdc-users.sh CSCU --dry-run          # show the plan, change nothing
#    ./load-pdc-users.sh --list-roles            # dump the realm's roles + groups
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

SCENARIO=""; PASSWORD=""; DRY=0; LIST_ROLES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --password) PASSWORD="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --list-roles) LIST_ROLES=1; shift ;;
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

# kcadm wrapper: logs in once per invocation batch using the container's own
# master-admin env; the server runs under the /keycloak relative path.
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

[ -n "$SCENARIO" ] || die "Pass a scenario id (CSCU/RETAIL/HEALTH/MFG) or --list-roles."
CSV="courseware/$SCENARIO/Platform/Workshop-00-Preflight/assets/users.csv"
[ -f "$CSV" ] || die "Roster not found: $CSV (is the $SCENARIO vertical checked out?)"
[ -n "$PASSWORD" ] || PASSWORD="$(default_password "$SCENARIO")"
[ -n "$PASSWORD" ] || die "No default password for $SCENARIO — pass --password."

command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python

echo
echo "  Loading $SCENARIO cast into Keycloak realm '$REALM' ($KC_CONTAINER)"
echo

# the realm's actual roles + groups, once (names only, one per line)
REALM_ROLES="$(kc "get roles -r $REALM --fields name" | sed -n 's/.*"name" : "\(.*\)".*/\1/p')"
REALM_GROUPS="$(kc "get groups -r $REALM --fields name,id")"

resolve_role() {  # display name -> realm role name (or empty)
  local norm alias
  norm="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/_/g;s/^_//;s/_$//')"
  alias="$(printf '%s\n' "$ROLE_ALIASES" | sed -n "s/^${norm}=//p" | head -1)"
  for cand in "$norm" "$alias"; do
    [ -n "$cand" ] || continue
    if printf '%s\n' "$REALM_ROLES" | grep -qx "$cand"; then echo "$cand"; return 0; fi
  done
  return 1
}

# CSV -> TAB rows: username, email, first, last, roles(;-joined)  (Notes has
# quoted commas, so real CSV parsing — no awk)
"$PY" - "$CSV" <<'PYEOF' | while IFS=$'\t' read -r U EMAIL FIRST LAST ROLES; do
import csv, sys
with open(sys.argv[1], newline="", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        email = (row.get("Email") or "").strip()
        if not email:
            continue
        print("\t".join([
            email.split("@")[0].lower(),
            email,
            (row.get("First_Name") or "").strip(),
            (row.get("Last_Name") or "").strip(),
            (row.get("PDC_Roles") or "").strip(),
        ]))
PYEOF
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
  kc "set-password -r $REALM --username $U --new-password '$PASSWORD'" >/dev/null \
    && ok "password set" || warn "set-password failed"

  # map each roster role -> realm role (fallback: same-named group)
  printf '%s' "$ROLES" | tr ';' '\n' | sed 's/^ *//;s/ *$//' | while read -r R; do
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
