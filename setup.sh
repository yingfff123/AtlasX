#!/usr/bin/env bash
# AtlasX 首次安装 — 默认 pull GHCR；密钥只写入本地 .env
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

die() { echo "[setup] $*" >&2; exit 1; }

"$ROOT/scripts/detect-os.sh" >/dev/null

if ! command -v docker >/dev/null 2>&1 \
  || { ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; }; then
  if [[ "$(id -u)" -eq 0 ]]; then
    "$ROOT/scripts/install-docker.sh"
  else
    die "未检测到 Docker/compose。请: sudo $ROOT/scripts/install-docker.sh"
  fi
fi

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

if [[ ! -f .env ]]; then
  cp .env.example .env
  if command -v python3 >/dev/null 2>&1; then
    MASTER="$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())' 2>/dev/null \
      || python3 -c 'import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())')"
    TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    MID="$(python3 -c 'import secrets; print("atlasx-" + secrets.token_hex(6))')"
  else
    MASTER="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')"
    TOKEN="$(openssl rand -hex 24)"
    MID="atlasx-$(openssl rand -hex 6)"
  fi
  awk -v m="$MASTER" -v t="$TOKEN" -v mid="$MID" '
    /^RADAR_MASTER_KEY=$/ { print "RADAR_MASTER_KEY=" m; next }
    /^RADAR_ACCESS_TOKEN=$/ { print "RADAR_ACCESS_TOKEN=" t; next }
    /^RADAR_MACHINE_ID=$/ { print "RADAR_MACHINE_ID=" mid; next }
    { print }
  ' .env > .env.tmp && mv .env.tmp .env
  chmod 600 .env
  echo "[setup] 已生成 .env（权限 600）"
  echo "[setup] RADAR_ACCESS_TOKEN=${TOKEN}"
  echo "[setup] RADAR_MACHINE_ID=${MID}"
  echo "[setup] 请立即保存 token；之后可用 Authorization: Bearer <token> 或 ?token="
else
  chmod 600 .env || true
fi

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
set_kv RADAR_DATABASE_URL "postgresql+psycopg://radar:radar@db:5432/radar"
# 确保有 machine id
if grep -q '^RADAR_MACHINE_ID=$' .env || ! grep -q '^RADAR_MACHINE_ID=' .env; then
  MID="$(python3 -c 'import secrets; print("atlasx-" + secrets.token_hex(6))' 2>/dev/null || echo "atlasx-$(openssl rand -hex 6)")"
  set_kv RADAR_MACHINE_ID "$MID"
  echo "[setup] 已写入 RADAR_MACHINE_ID=${MID}"
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

if [[ -z "${RADAR_MACHINE_ID:-}" ]]; then
  die "RADAR_MACHINE_ID 为空；请写入 .env 后重试"
fi

COMPOSE_ARGS=(-f docker-compose.yml)
USE_LITE=0

# 内存 < 3.5GiB 自动叠加 lite
MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 999999999)"
if [[ "$MEM_KB" -lt 3600000 ]] && [[ -f docker-compose.lite.yml ]]; then
  USE_LITE=1
  COMPOSE_ARGS+=(-f docker-compose.lite.yml)
  echo "[setup] 检测到内存约 $((MEM_KB/1024))MiB < 3500MiB → 启用 docker-compose.lite.yml"
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/pull-release.sh"

echo "[setup] 按本机架构拉镜像（约 1.3GB）。默认 ghcr.1ms.run；南大源层文件经常 0B 已自动跳过"
atlasx_pull_release || die "pull 失败。可设 ATLASX_SKIP_MIRROR=1 仅走官方源，或检查网络"

compose "${COMPOSE_ARGS[@]}" up -d --pull never
export POSTGRES_USER="${POSTGRES_USER:-radar}" POSTGRES_DB="${POSTGRES_DB:-radar}"
"$ROOT/scripts/wait-db.sh" docker-compose.yml

# 库表由容器 entrypoint 的 docker_db_init 完成；这里只等 web healthy/up
echo "[setup] 等待 web 就绪…"
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${ATLASX_HTTP_PORT:-8000}/healthz" >/dev/null 2>&1 \
    || curl -fsS "http://127.0.0.1:${ATLASX_HTTP_PORT:-8000}/" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
IP="${IP:-127.0.0.1}"
PORT="${ATLASX_HTTP_PORT:-8000}"
TOKEN_SHOW="$(grep '^RADAR_ACCESS_TOKEN=' .env | cut -d= -f2- || true)"
echo ""
echo "[setup] 完成"
echo "  UI: http://${IP}:${PORT}/?token=${TOKEN_SHOW}"
echo "  请登录后立刻修改默认管理员密码；勿将 .env 或 GitHub PAT 放入镜像/仓库"
if [[ "$USE_LITE" == "1" ]]; then
  echo "  模式: lite（低内存）；升级仍用: bash update.sh"
else
  echo "  升级: bash update.sh"
fi
