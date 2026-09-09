#!/usr/bin/env bash
# 等待 compose 服务 db healthy
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="${1:-docker-compose.yml}"
TRIES="${2:-60}"

cd "$ROOT"
compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" "$@"
  else
    docker-compose -f "$COMPOSE_FILE" "$@"
  fi
}

for i in $(seq 1 "$TRIES"); do
  st="$(compose ps db --format json 2>/dev/null | head -1 || true)"
  if compose exec -T db pg_isready -U "${POSTGRES_USER:-radar}" -d "${POSTGRES_DB:-radar}" >/dev/null 2>&1; then
    echo "[wait-db] ready (${i})"
    exit 0
  fi
  sleep 2
done
echo "[wait-db] timeout" >&2
exit 1
