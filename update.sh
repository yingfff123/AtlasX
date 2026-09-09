#!/usr/bin/env bash
# 升级：保留 volumes；不覆盖 MASTER_KEY / ACCESS_TOKEN
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "[update] 缺少 .env，请先 setup.sh" >&2; exit 1; }

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

ATLASX_DOCKER_ROOT="$ROOT"
set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" .env; then
    awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' .env > .env.tmp && mv .env.tmp .env
  else
    echo "${k}=${v}" >> .env
  fi
}
set_kv ATLASX_DOCKER_ROOT "$ATLASX_DOCKER_ROOT"

# shellcheck disable=SC1091
set -a; source .env; set +a

COMPOSE_ARGS=(-f docker-compose.yml)
MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 999999999)"
if [[ "$MEM_KB" -lt 3600000 ]] && [[ -f docker-compose.lite.yml ]]; then
  COMPOSE_ARGS+=(-f docker-compose.lite.yml)
  echo "[update] 低内存 → 叠加 docker-compose.lite.yml"
fi

if [[ -d .git ]]; then
  git pull --ff-only || echo "[update] git pull 跳过/失败（可忽略）"
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/pull-release.sh"

atlasx_pull_release "${COMPOSE_ARGS[@]}" || { echo "[update] pull 失败" >&2; exit 1; }

compose "${COMPOSE_ARGS[@]}" up -d
# wait-db 只接受单个 -f 文件名；用主 compose
"$ROOT/scripts/wait-db.sh" docker-compose.yml

echo "[update] 完成（atlasx_pgdata / atlasx_engine / atlasx_updates / atlasx_var 已保留）"
echo "[update] 镜像: ${ATLASX_IMAGE:-ghcr.nju.edu.cn/yingfff123/atlasx-docker}:${ATLASX_IMAGE_TAG:-0.2.7.4}"
echo "[update] 库表由 entrypoint 自动处理；引擎热更后请: docker compose restart web worker"
