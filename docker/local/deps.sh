#!/usr/bin/env bash
# Finture local — instala node_modules no volume "node_modules".
# É o ÚNICO serviço de app com acesso à internet (registry do npm), e não
# recebe nenhuma variável de ambiente da aplicação.
set -euo pipefail
cd /app

current="$(sha256sum pnpm-lock.yaml | cut -d' ' -f1)"
installed="$(cat node_modules/.finture-pnpm-lock.sha 2>/dev/null || true)"

if [ "$current" = "$installed" ] && [ "${FORCE_DEPS:-false}" != "true" ]; then
  echo "[finture-local] node_modules já corresponde ao pnpm-lock.yaml."
  exit 0
fi

echo "[finture-local] Instalando dependências JS (pnpm install --frozen-lockfile)..."
# Store dentro do próprio volume: mesmo filesystem, hard links funcionam.
pnpm install --frozen-lockfile --store-dir /app/node_modules/.pnpm-store --config.confirmModulesPurge=false
echo "$current" > node_modules/.finture-pnpm-lock.sha
echo "[finture-local] Dependências JS prontas."
