# Finture — alvos do ambiente local Docker (incluído pelo Makefile da raiz).
# Todos delegam para script/local-dev, que também pode ser usado sem make
# (ex.: no Git Bash do Windows: bash script/local-dev dev).
LOCAL_DEV := bash script/local-dev

.PHONY: dev stop logs logs-web logs-worker db-reset db-migrate db-seed test clean \
	local-setup local-build local-deps local-down local-restart local-status local-console \
	local-shell local-attach local-db-console local-check local-simulate local-test-js local-scan-secrets

dev:            ## sobe o ambiente completo
	@$(LOCAL_DEV) dev
stop:           ## para os containers (dados preservados)
	@$(LOCAL_DEV) stop
logs:           ## logs de todos os serviços
	@$(LOCAL_DEV) logs
logs-web:       ## logs do Rails/Puma
	@$(LOCAL_DEV) logs-web
logs-worker:    ## logs do Sidekiq
	@$(LOCAL_DEV) logs-worker
db-reset:       ## APAGA e recria só o banco local (com confirmação)
	@$(LOCAL_DEV) db-reset
db-migrate:     ## migrations pendentes
	@$(LOCAL_DEV) db-migrate
db-seed:        ## seeds sintéticas Finture (idempotente)
	@$(LOCAL_DEV) db-seed
test:           ## rspec (ARGS="spec/models/finture" para filtrar)
	@$(LOCAL_DEV) test $(ARGS)
clean:          ## limpeza com confirmação (ARGS="--volumes" | "--image" | "--all")
	@$(LOCAL_DEV) clean $(ARGS)

local-setup:
	@$(LOCAL_DEV) setup
local-build:
	@$(LOCAL_DEV) build
local-deps:
	@$(LOCAL_DEV) deps
local-down:
	@$(LOCAL_DEV) down
local-restart:
	@$(LOCAL_DEV) restart $(ARGS)
local-status:
	@$(LOCAL_DEV) status
local-console:
	@$(LOCAL_DEV) console
local-shell:
	@$(LOCAL_DEV) shell
local-attach:
	@$(LOCAL_DEV) attach $(ARGS)
local-db-console:
	@$(LOCAL_DEV) db-console
local-check:
	@$(LOCAL_DEV) check
local-simulate:
	@$(LOCAL_DEV) simulate
local-test-js:
	@$(LOCAL_DEV) test-js $(ARGS)
local-scan-secrets:
	@$(LOCAL_DEV) scan-secrets
