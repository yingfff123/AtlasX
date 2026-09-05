#!/usr/bin/env bash
# 升级：保留 PG volume；不覆盖 MASTER_KEY / ACCESS_TOKEN；密钥不进镜像
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "[update] 缺少 .env，请先 setup.sh" >&2; exit 1; }

compose() {
  local f="$1"; shift
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$f" "$@"
  else
    docker-compose -f "$f" "$@"
  fi
}

# 刷新绝对路径（不碰密钥）
ATLASX_DOCKER_ROOT="$ROOT"
ATLASX_CANDIDATE="$(cd "$ROOT/../AtlasX" 2>/dev/null && pwd || true)"
set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" .env; then
    awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' .env > .env.tmp && mv .env.tmp .env
  else
    echo "${k}=${v}" >> .env
  fi
}
set_kv ATLASX_DOCKER_ROOT "$ATLASX_DOCKER_ROOT"
if [[ -n "$ATLASX_CANDIDATE" && -f "$ATLASX_CANDIDATE/pyproject.toml" ]]; then
  set_kv ATLASX_ROOT "$ATLASX_CANDIDATE"
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

RELEASE="${ATLASX_RELEASE:-0}"
if [[ -d .git ]]; then
  git pull --ff-only || echo "[update] git pull 跳过/失败（可忽略）"
fi

if [[ "$RELEASE" == "1" ]]; then
  COMPOSE_FILE="docker-compose.yml"
  compose "$COMPOSE_FILE" pull
else
  COMPOSE_FILE="docker-compose.mvp.yml"
  [[ -n "${ATLASX_ROOT:-}" ]] || { echo "[update] 缺 ATLASX_ROOT" >&2; exit 1; }
  compose "$COMPOSE_FILE" build
fi

compose "$COMPOSE_FILE" up -d
"$ROOT/scripts/wait-db.sh" "$COMPOSE_FILE"
compose "$COMPOSE_FILE" run --rm --no-deps web alembic upgrade head

echo "[update] 完成（volume atlasx_pgdata 已保留）"
if [[ "$RELEASE" == "1" ]]; then
  echo "[update] 镜像: ${ATLASX_IMAGE}:${ATLASX_IMAGE_TAG}"
else
  echo "[update] 镜像: atlasx:mvp"
fi
