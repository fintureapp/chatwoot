#!/usr/bin/env bash
# Finture local — entrypoint dos serviços rails/sidekiq/vite/db-prepare.
# Falha cedo (sem instalar nada pela rede) se a imagem ou o node_modules
# estiverem desatualizados em relação aos lockfiles do repositório.
set -euo pipefail

cd /app

fail() {
  echo "[finture-local] $*" >&2
  exit 1
}

# 1. Isolamento: estes valores são fixados pelo compose. Se algo mudou, para aqui
#    antes de qualquer conexão (a trava completa roda no boot do Rails).
case "${POSTGRES_HOST:-}" in
  postgres) ;;
  *) fail "POSTGRES_HOST precisa ser 'postgres' (banco do compose local)." ;;
esac
case "${POSTGRES_DATABASE:-}" in
  chatwoot_local_dev|chatwoot_local_test) ;;
  *) fail "POSTGRES_DATABASE precisa ser chatwoot_local_dev ou chatwoot_local_test." ;;
esac
case "${REDIS_URL:-}" in
  redis://redis:6379*) ;;
  *) fail "REDIS_URL precisa apontar para o redis do compose local." ;;
esac
[ "${RAILS_ENV:-}" = "production" ] && fail "RAILS_ENV=production não é permitido aqui."

# 2. Gems: a imagem foi construída com o Gemfile.lock atual?
expected_gems="$(cat /usr/local/bundle/.finture-gemfile-lock.sha 2>/dev/null || true)"
current_gems="$(sha256sum Gemfile.lock | cut -d' ' -f1)"
if [ "$expected_gems" != "$current_gems" ]; then
  fail "Gemfile.lock mudou desde o build da imagem. Rode: make build (ou script/local-dev build)."
fi

# 3. node_modules: o serviço deps instalou para o pnpm-lock.yaml atual?
if [ "${FINTURE_NEEDS_NODE_MODULES:-true}" = "true" ]; then
  expected_node="$(cat node_modules/.finture-pnpm-lock.sha 2>/dev/null || true)"
  current_node="$(sha256sum pnpm-lock.yaml | cut -d' ' -f1)"
  if [ "$expected_node" != "$current_node" ]; then
    fail "node_modules desatualizado para o pnpm-lock.yaml. Rode: make deps (ou script/local-dev deps)."
  fi
fi

mkdir -p tmp/pids tmp/cache log storage
rm -f tmp/pids/server.pid

exec "$@"
