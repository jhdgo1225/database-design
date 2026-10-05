# ---------------------------------------------------------------------------
# PostgreSQL (docker-compose.yml, project "database-optimization") -- targets
# below are unprefixed (up, down, psql, ...) and touch ONLY the postgres
# container. See the ORACLE_* section further down for the Oracle container:
# the two stacks live in separate compose files/projects and are never
# started, stopped, or otherwise driven by the same target.
# ---------------------------------------------------------------------------
PG_COMPOSE    := docker compose
CONTAINER     := db-optimization-postgres
PG_USER       := postgres
DATABASES     := library cinema school bicycle_rental pos
DB_COUNT      := $(words $(DATABASES))
DB_LIST_SQL   := $(shell printf "%s" "$(DATABASES)" | tr ' ' '\n' | sed "s/.*/'&'/" | paste -sd, -)

# DB=<name> make psql   (defaults to the postgres maintenance db)
DB ?= postgres

# ---------------------------------------------------------------------------
# Oracle (docker-compose.oracle.yml, separate project "db-optimization-oracle")
# -- targets below are all prefixed oracle- and touch ONLY the oracle
# container/network/volume. Its own compose file + project name keep it
# fully isolated from the postgres stack above.
# ---------------------------------------------------------------------------
ORACLE_COMPOSE   := docker compose -f docker-compose.oracle.yml -p db-optimization-oracle
ORACLE_CONTAINER := db-optimization-oracle
ORACLE_USER      := system
ORACLE_PASSWORD  ?= oracle
ORACLE_PDB       ?= FREEPDB1

.DEFAULT_GOAL := up
.PHONY: all up start check-dbs wait-ready down stop restart re remove clean fclean status logs psql sh help \
	oracle-up oracle-start oracle-wait-ready oracle-down oracle-stop oracle-restart oracle-re oracle-remove \
	oracle-clean oracle-fclean oracle-status oracle-logs oracle-sqlplus oracle-sh oracle-help

## default target: make sure the container exists, is running, and all 5
## project databases are present. Only touches what is actually missing.
all: up

up:
	@if [ -z "$$(docker ps -aq -f name=^/$(CONTAINER)$$)" ]; then \
		echo "==> container '$(CONTAINER)' does not exist. creating and starting..."; \
		$(PG_COMPOSE) up -d; \
	elif [ -z "$$(docker ps -q -f name=^/$(CONTAINER)$$)" ]; then \
		echo "==> container '$(CONTAINER)' exists but is stopped. starting..."; \
		$(PG_COMPOSE) start; \
	else \
		echo "==> container '$(CONTAINER)' is already running."; \
	fi
	@$(MAKE) --no-print-directory wait-ready
	@$(MAKE) --no-print-directory check-dbs

wait-ready:
	@echo "==> waiting for postgres to accept connections..."
	@until docker exec $(CONTAINER) pg_isready -U $(PG_USER) >/dev/null 2>&1; do sleep 1; done
	@echo "==> postgres is ready."

## checks how many of the 5 project databases exist and creates only the
## missing ones (see docker/init-db/00-init-databases.sh for the per-db logic).
## on first boot, pg_isready in wait-ready can succeed against the throwaway
## server postgres uses to run /docker-entrypoint-initdb.d/*, right before it
## shuts that down and restarts the real one -- so retry through that window
## instead of failing on the transient "database system is shutting down".
check-dbs:
	@i=0; \
	while ! present=$$(docker exec $(CONTAINER) psql -U $(PG_USER) -tAc \
		"SELECT count(*) FROM pg_database WHERE datname IN ($(DB_LIST_SQL))" 2>/dev/null); do \
		i=$$((i + 1)); \
		if [ $$i -ge 30 ]; then \
			echo "==> postgres did not settle after restart; giving up"; \
			exit 1; \
		fi; \
		sleep 1; \
	done; \
	if [ "$$present" = "$(DB_COUNT)" ]; then \
		echo "==> all $(DB_COUNT) databases already present: $(DATABASES)"; \
	else \
		echo "==> only $$present/$(DB_COUNT) databases present. creating the missing ones..."; \
		docker exec $(CONTAINER) sh /docker-entrypoint-initdb.d/00-init-databases.sh; \
	fi

## stop and remove the container/network, but keep the data volume
down:
	$(PG_COMPOSE) down

## stop the container without removing it
stop:
	$(PG_COMPOSE) stop

## restart the existing container in place
restart:
	$(PG_COMPOSE) restart

## rebuild everything from scratch: wipe the volume, then bring it back up
## and reload all 5 databases
re: remove up

## stop and remove the container/network AND the data volume (all 5 DBs lost)
remove:
	$(PG_COMPOSE) down -v

fclean: remove
clean: down

status:
	@$(PG_COMPOSE) ps
	@docker exec $(CONTAINER) psql -U $(PG_USER) -tAc \
		"SELECT datname FROM pg_database WHERE datname IN ($(DB_LIST_SQL)) ORDER BY datname" \
		2>/dev/null || echo "==> container is not reachable"

logs:
	$(PG_COMPOSE) logs -f

## open a psql shell: DB=library make psql
psql:
	docker exec -it $(CONTAINER) psql -U $(PG_USER) -d $(DB)

sh:
	docker exec -it $(CONTAINER) sh

help:
	@echo "make [up]        create/start the container and ensure all 5 DBs exist (default)"
	@echo "make down        stop + remove container (keeps data volume)"
	@echo "make stop        stop container without removing it"
	@echo "make restart     restart the existing container"
	@echo "make re          remove + up (full rebuild, data reloaded from scratch)"
	@echo "make remove      stop + remove container AND data volume"
	@echo "make status      show container state and which DBs exist"
	@echo "make logs        follow container logs"
	@echo "make psql DB=x   open a psql shell to database x (default: postgres)"
	@echo ""
	@echo "Oracle container is managed separately: make oracle-help"

# ===========================================================================
# Oracle -- fully independent of everything above. Every target here talks
# only to $(ORACLE_CONTAINER) via $(ORACLE_COMPOSE) (docker-compose.oracle.yml,
# project "db-optimization-oracle"). None of the postgres targets above ever
# reference these, and these never reference postgres.
# ===========================================================================

oracle-up:
	@if [ -z "$$(docker ps -aq -f name=^/$(ORACLE_CONTAINER)$$)" ]; then \
		echo "==> container '$(ORACLE_CONTAINER)' does not exist. creating and starting..."; \
		$(ORACLE_COMPOSE) up -d; \
	elif [ -z "$$(docker ps -q -f name=^/$(ORACLE_CONTAINER)$$)" ]; then \
		echo "==> container '$(ORACLE_CONTAINER)' exists but is stopped. starting..."; \
		$(ORACLE_COMPOSE) start; \
	else \
		echo "==> container '$(ORACLE_CONTAINER)' is already running."; \
	fi
	@$(MAKE) --no-print-directory oracle-wait-ready

oracle-start: oracle-up

## the image ships healthcheck.sh, which only reports success once the
## instance AND its pluggable database are fully open -- unlike pg_isready
## this has no throwaway-instance race, but first-time setup (creating the
## data files) can take a couple of minutes, hence the long timeout.
oracle-wait-ready:
	@echo "==> waiting for oracle to accept connections (first boot can take a few minutes)..."
	@i=0; \
	until docker exec $(ORACLE_CONTAINER) healthcheck.sh >/dev/null 2>&1; do \
		i=$$((i + 1)); \
		if [ $$i -ge 180 ]; then \
			echo "==> oracle did not become ready in time"; \
			exit 1; \
		fi; \
		sleep 2; \
	done
	@echo "==> oracle is ready."

## stop and remove the oracle container/network, but keep the data volume
oracle-down:
	$(ORACLE_COMPOSE) down

## stop the oracle container without removing it
oracle-stop:
	$(ORACLE_COMPOSE) stop

## restart the existing oracle container in place
oracle-restart:
	$(ORACLE_COMPOSE) restart

## rebuild the oracle container from scratch: wipe its volume, bring it back up
oracle-re: oracle-remove oracle-up

## stop and remove the oracle container/network AND its data volume
oracle-remove:
	$(ORACLE_COMPOSE) down -v

oracle-fclean: oracle-remove
oracle-clean: oracle-down

oracle-status:
	@$(ORACLE_COMPOSE) ps

oracle-logs:
	$(ORACLE_COMPOSE) logs -f

## open a sqlplus shell to the default pluggable database as SYSTEM
oracle-sqlplus:
	docker exec -it $(ORACLE_CONTAINER) sqlplus $(ORACLE_USER)/$(ORACLE_PASSWORD)@//localhost:1521/$(ORACLE_PDB)

oracle-sh:
	docker exec -it $(ORACLE_CONTAINER) bash

oracle-help:
	@echo "make oracle-up          create/start the oracle container (waits until ready)"
	@echo "make oracle-down        stop + remove oracle container (keeps data volume)"
	@echo "make oracle-stop        stop oracle container without removing it"
	@echo "make oracle-restart     restart the existing oracle container"
	@echo "make oracle-re          oracle-remove + oracle-up (full rebuild)"
	@echo "make oracle-remove      stop + remove oracle container AND its data volume"
	@echo "make oracle-status      show oracle container state"
	@echo "make oracle-logs        follow oracle container logs"
	@echo "make oracle-sqlplus     open a sqlplus shell (system/\$$ORACLE_PASSWORD@\$$ORACLE_PDB)"
