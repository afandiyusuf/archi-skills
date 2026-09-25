# SLS task folder Makefile.
# Lives at the root of ~/Documents/Workspace/sls/<task>/ (and staging/).
# Managed by the setup-worktree skill; new task folders get a fresh copy.
#
# Only one folder can run the stack at a time (API on 8081, CMS on 5173).
# The guards below stop you and name the folder that is already running.

TASK      := $(notdir $(CURDIR))
API_DIR   := sentec-loyalty-system-api
WEB_DIR   := sentec-loyalty-system-web
STAGING   := $(abspath $(CURDIR)/../staging)

API_PORT  := 8081
WEB_PORT  := 5173

API_LOCAL_URL   := http://localhost:$(API_PORT)
API_STAGING_URL := https://d2oe9cfa029ln2.cloudfront.net

# Per-task overrides (for example `API := staging`) go in local.mk.
-include local.mk

# Which API the CMS talks to: local (default) or staging.
API ?= local
ifeq ($(API),staging)
  WEB_API_URL := $(API_STAGING_URL)
else
  WEB_API_URL := $(API_LOCAL_URL)
endif

COMPOSE := docker compose -p sls-$(TASK) --project-directory $(API_DIR) -f $(API_DIR)/docker-compose.yml

# Ignored files that are copied from staging/ (edit them there only).
API_SECRETS := config.json scripts/config.json docs/bruno/membership-sentec-bruno/environments/local.secrets.bru
WEB_SECRETS := .env

.PHONY: help up api web down logs status sync-secrets guard-api guard-web

## help: show this help
help:
	@echo "Task: $(TASK)   (CMS -> $(API) API: $(WEB_API_URL))"
	@echo
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  make /'

## up: rebuild + start the API (background), then run the CMS (foreground). API=staging skips the local API.
up:
ifeq ($(API),staging)
	@$(MAKE) --no-print-directory web
else
	@$(MAKE) --no-print-directory api
	@$(MAKE) --no-print-directory web
endif

## api: rebuild and start the API in Docker on :8081 (background)
api: guard-api
	$(COMPOSE) up --build -d
	@echo "API running from $(TASK). Logs: make logs   Stop: make down"

## web: run the CMS dev server on :5173 (API=staging to use the staging API)
web: guard-web
	@echo "CMS -> $(WEB_API_URL)"
	cd $(WEB_DIR) && VITE_API_BASE_URL=$(WEB_API_URL) npm run dev -- --port $(WEB_PORT) --strictPort

## down: stop this folder's API containers
down:
	$(COMPOSE) down

## logs: follow this folder's API logs
logs:
	$(COMPOSE) logs -f

## status: show branches and which folder owns ports 8081 / 5173
status:
	@echo "Task: $(TASK)"
	@printf "  api: %s\n" "$$(git -C $(API_DIR) branch --show-current)"
	@printf "  web: %s\n" "$$(git -C $(WEB_DIR) branch --show-current)"
	@owner=$$(docker ps --filter "publish=$(API_PORT)" --format '{{.Label "com.docker.compose.project.working_dir"}}' | head -n1); \
	  printf "  :$(API_PORT) -> %s\n" "$${owner:-free}"
	@pid=$$(ss -ltnpH "sport = :$(WEB_PORT)" 2>/dev/null | grep -o 'pid=[0-9]*' | head -n1 | cut -d= -f2); \
	  if [ -n "$$pid" ]; then printf "  :$(WEB_PORT) -> %s\n" "$$(readlink /proc/$$pid/cwd)"; else echo "  :$(WEB_PORT) -> free"; fi

## sync-secrets: copy config.json / .env etc. from staging/ into this folder (old ones kept as *.~N~)
sync-secrets:
	@if [ "$(CURDIR)" = "$(STAGING)" ]; then echo "This is staging/ itself; nothing to sync."; exit 0; fi
	@for f in $(API_SECRETS); do \
	  if [ -f "$(STAGING)/$(API_DIR)/$$f" ]; then mkdir -p "$(API_DIR)/$$(dirname $$f)"; cp --backup=numbered "$(STAGING)/$(API_DIR)/$$f" "$(API_DIR)/$$f"; echo "  api/$$f"; fi; \
	done
	@for f in $(WEB_SECRETS); do \
	  if [ -f "$(STAGING)/$(WEB_DIR)/$$f" ]; then cp --backup=numbered "$(STAGING)/$(WEB_DIR)/$$f" "$(WEB_DIR)/$$f"; echo "  web/$$f"; fi; \
	done

guard-api:
	@owner=$$(docker ps --filter "publish=$(API_PORT)" --format '{{.Label "com.docker.compose.project.working_dir"}}' | head -n1); \
	if [ -n "$$owner" ] && [ "$$owner" != "$(CURDIR)/$(API_DIR)" ]; then \
	  echo "Port $(API_PORT) is already used by: $$owner"; \
	  echo "Stop it first (make down in that folder, or docker compose down there)."; exit 1; \
	fi; \
	if [ -z "$$owner" ] && ss -ltnH "sport = :$(API_PORT)" 2>/dev/null | grep -q .; then \
	  echo "Port $(API_PORT) is used by a non-Docker process (go run?). Stop it first."; exit 1; \
	fi

guard-web:
	@pid=$$(ss -ltnpH "sport = :$(WEB_PORT)" 2>/dev/null | grep -o 'pid=[0-9]*' | head -n1 | cut -d= -f2); \
	if [ -n "$$pid" ]; then \
	  echo "Port $(WEB_PORT) is already used by pid $$pid in: $$(readlink /proc/$$pid/cwd 2>/dev/null || echo unknown)"; \
	  echo "Stop that dev server first (Ctrl+C in its terminal)."; exit 1; \
	elif ss -ltnH "sport = :$(WEB_PORT)" 2>/dev/null | grep -q .; then \
	  echo "Port $(WEB_PORT) is in use by another user's process. Stop it first."; exit 1; \
	fi
