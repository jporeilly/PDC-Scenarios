# PDC-Scenarios — one make entry per vertical
#
#   make scenario ID=CSCU    select the vertical + lab up + load its data
#   make select   ID=CSCU    sparse-pull just that vertical (courseware+assets)
#   make up                  shared lab (postgres 5433 + minio) up
#   make load     ID=CSCU    create/load that vertical's db + bucket
#   make pack     ID=CSCU    install its domain pack + roster into the Glossary app
#   make users    ID=CSCU    load that vertical's cast into PDC's Keycloak
#   make users-check ID=CSCU dry run: show the plan, change nothing
#   make users-roles         list the realm's ACTUAL roles + groups (no changes)
#   make remove   ID=CSCU    drop that vertical's db + bucket
#   make status              lab containers + which vertical is selected
#   make down                stop the lab (data volumes survive)
#   make destroy             stop the lab and ERASE all scenario data volumes
#
# ID accepts lowercase too (make scenario ID=cscu).

LAB     := data_sources/lab
IDU      = $(shell echo $(ID) | tr a-z A-Z)

.PHONY: scenario select up load pack users users-check users-roles remove status down destroy _need_id _users_note

scenario: _need_id select up load
	@echo ""
	@echo "  Vertical $(IDU) ready: sources loaded, courseware in courseware/$(IDU)/"
	@echo "  Next: make pack ID=$(IDU)   (install its domain pack into the Glossary app)"

select: _need_id
	@PDC_SCEN_QUIET=1 bash select-vertical.sh $(IDU)

up: $(LAB)/.env
	@$(MAKE) -C $(LAB) up

load: _need_id $(LAB)/.env
	@$(MAKE) -C $(LAB) load SCENARIO=$(IDU)

pack: _need_id
	@bash install-scenario.sh $(IDU)

remove: _need_id
	@$(MAKE) -C $(LAB) remove SCENARIO=$(IDU)

status:
	@echo "Selected vertical:" \
	  $$(git sparse-checkout list 2>/dev/null | sed -n 's#^data_sources/##p' | grep -v '^lab$$' || echo '(all / none)')
	@$(MAKE) -C $(LAB) status 2>/dev/null || docker ps --filter name=demo- --format 'table {{.Names}}\t{{.Status}}'

down:
	@$(MAKE) -C $(LAB) clean

destroy:
	@$(MAKE) -C $(LAB) destroy

$(LAB)/.env:
	@test -d $(LAB) || { echo "lab not checked out — run: make select ID=<vertical>"; exit 1; }
	@cp $(LAB)/.env.example $@ 2>/dev/null && echo "  created $(LAB)/.env from .env.example — review the credentials" || true

# ---------------------------------------------------------------- users ----
# Two runners, same roster and the same role matching:
#   load-pdc-users.sh   ON the lab VM  - docker exec + kcadm.sh in the container
#   load-pdc-users.ps1  from Windows   - Keycloak Admin REST API over HTTPS
# make picks the shell one when docker is present (you are on the VM), and tells
# you the PowerShell command when it is not, rather than failing obscurely.
_users_note:
	@echo ""
	@echo "  Loading the cast into Keycloak realm 'pdc'."
	@echo "  Checkpoints: connect -> roster -> password policy -> realm roles -> load -> verify."
	@echo "  Idempotent: an existing user is KEPT, with password and roles re-applied."
	@echo ""

users: _need_id _users_note
	@if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q um-keycloak; then 	  echo "  Keycloak container found - using the VM runner."; 	  bash load-pdc-users.sh $(IDU); 	else 	  echo "  No Keycloak container here, so this is not the lab VM."; 	  echo "  Run the Windows runner from PowerShell instead:"; 	  echo ""; 	  echo "      .\load-pdc-users.ps1 -Scenario $(IDU) -BaseUrl https://pentaho.io -SkipTlsCheck"; 	  echo ""; 	  echo "  It uses Keycloak's Admin REST API - no docker, no SSH."; 	  echo "  Add -DryRun first, and -FixPolicy if the realm rejects the lab passwords."; 	  exit 1; 	fi

users-check: _need_id
	@echo "  DRY RUN - showing the plan for $(IDU), changing nothing."
	@if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q um-keycloak; then 	  bash load-pdc-users.sh $(IDU) --dry-run; 	else 	  echo "      .\load-pdc-users.ps1 -Scenario $(IDU) -DryRun"; 	fi

users-roles:
	@echo "  The realm's ACTUAL roles and groups. Roster names are matched against"
	@echo "  these, never assumed - extend the alias table if one does not match."
	@if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q um-keycloak; then 	  bash load-pdc-users.sh --list-roles; 	else 	  echo "      .\load-pdc-users.ps1 -ListRoles"; 	fi

_need_id:
	@test -n "$(ID)" || { echo "usage: make $(MAKECMDGOALS) ID=<CSCU|RETAIL|HEALTH|MFG>"; exit 1; }
