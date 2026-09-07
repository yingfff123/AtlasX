#!/usr/bin/env bash
# AtlasX 首次安装（Debian / Kali）— 密钥只写入本地 .env，永不进镜像
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
  local f="$1"; shift
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$f" "$@"
  else
    docker-compose -f "$f" "$@"
  fi
}

ATLASX_CANDIDATE="$(cd "$ROOT/../AtlasX" 2>/dev/null && pwd || true)"

if [[ ! -f .env ]]; then
  cp .env.example .env
  # 生成 Fernet key 与 access token（不依赖已安装 cryptography）
  if command -v python3 >/dev/null 2>&1; then
    MASTER="$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())' 2>/dev/null \
      || python3 -c 'import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())')"
    TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  else
    MASTER="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')"
    TOKEN="$(openssl rand -hex 24)"
  fi
  # 只改空值行，不回显密钥到终端日志文件以外的地方时仍打印一次给用户
  awk -v m="$MASTER" -v t="$TOKEN" '
    /^RADAR_MASTER_KEY=$/ { print "RADAR_MASTER_KEY=" m; next }
    /^RADAR_ACCESS_TOKEN=$/ { print "RADAR_ACCESS_TOKEN=" t; next }
    { print }
  ' .env > .env.tmp && mv .env.tmp .env
  chmod 600 .env
  echo "[setup] 已生成 .env（权限 600）"
  echo "[setup] RADAR_ACCESS_TOKEN=${TOKEN}"
  echo "[setup] 请立即保存上述 token；之后可用 Authorization: Bearer <token> 或 ?token="
else
  chmod 600 .env || true
fi

# 写入绝对路径供 mvp build
ATLASX_DOCKER_ROOT="$ROOT"
if [[ -n "$ATLASX_CANDIDATE" && -f "$ATLASX_CANDIDATE/pyproject.toml" ]]; then
  ATLASX_ROOT="$ATLASX_CANDIDATE"
else
  ATLASX_ROOT=""
fi

# 更新/注入路径变量（保留已有密钥）
set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" .env; then
    awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' .env > .env.tmp && mv .env.tmp .env
  else
    echo "${k}=${v}" >> .env
  fi
}
set_kv ATLASX_DOCKER_ROOT "$ATLASX_DOCKER_ROOT"
set_kv ATLASX_ROOT "${ATLASX_ROOT}"
set_kv RADAR_DATABASE_URL "postgresql+psycopg://radar:radar@db:5432/radar"

# shellcheck disable=SC1091
set -a; source .env; set +a

RELEASE="${ATLASX_RELEASE:-0}"
COMPOSE_FILE="docker-compose.mvp.yml"

if [[ "$RELEASE" == "1" ]]; then
  echo "[setup] ATLASX_RELEASE=1 → 尝试 pull"
  if compose docker-compose.yml pull; then
    COMPOSE_FILE="docker-compose.yml"
  else
    die "pull 失败。可设 ATLASX_RELEASE=0 并用旁路 ../AtlasX 走 MVP build"
  fi
else
  [[ -n "$ATLASX_ROOT" ]] || die "未找到旁路主仓 ../AtlasX。请将 AtlasX 与 AtlasX 放在同一父目录，或设置 ATLASX_RELEASE=1 拉镜像"
  echo "[setup] MVP build context: $ATLASX_ROOT"
  compose "$COMPOSE_FILE" build
fi

compose "$COMPOSE_FILE" up -d
export POSTGRES_USER="${POSTGRES_USER:-radar}" POSTGRES_DB="${POSTGRES_DB:-radar}"
"$ROOT/scripts/wait-db.sh" "$COMPOSE_FILE"

echo "[setup] migrate…"
compose "$COMPOSE_FILE" run --rm --no-deps web alembic upgrade head

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
IP="${IP:-127.0.0.1}"
PORT="${ATLASX_HTTP_PORT:-8000}"
echo ""
echo "[setup] 完成"
echo "  UI: http://${IP}:${PORT}/"
echo "  认证: Authorization: Bearer \$RADAR_ACCESS_TOKEN  或  ?token="
echo "  请登录后立刻修改默认管理员密码；勿将 .env 或 GitHub PAT 放入镜像/仓库"
echo "  升级: bash update.sh"
