# PDC-Scenarios — one make entry per vertical
#
#   make scenario ID=CSCU    select the vertical + lab up + load its data
#   make select   ID=CSCU    sparse-pull just that vertical (courseware+assets)
#   make up                  shared lab (postgres 5433 + minio) up
#   make load     ID=CSCU    create/load that vertical's db + bucket
#   make pack     ID=CSCU    install its domain pack + roster into the Glossary app
#   make remove   ID=CSCU    drop that vertical's db + bucket
#   make status              lab containers + which vertical is selected
#   make down                stop the lab (data volumes survive)
#   make destroy             stop the lab and ERASE all scenario data volumes
#
# ID accepts lowercase too (make scenario ID=cscu).

LAB     := data_sources/lab
IDU      = $(shell echo $(ID) | tr a-z A-Z)

.PHONY: scenario select up load pack remove status down destroy _need_id

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

_need_id:
	@test -n "$(ID)" || { echo "usage: make $(MAKECMDGOALS) ID=<CSCU|RETAIL|HEALTH|MFG>"; exit 1; }
