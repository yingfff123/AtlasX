#!/bin/sh
# 容器入口：引擎 drop-in → 自动建库表（空库可直接用）→ 启动 web/worker
set -eu

# Pro 一证一机：web/worker 两容器 hostname 不同。未设 RADAR_MACHINE_ID 会分叉。
if [ -z "${RADAR_MACHINE_ID:-}" ]; then
  echo "[entrypoint] FATAL: RADAR_MACHINE_ID required — set the same value for web+worker in .env" >&2
  exit 1
fi

# worker 跑 ksubdomain 原生爆破需要 NET_RAW；无能力时采集器自动 DNS 回退（仍产出）
case " $* " in
  *" worker "*|*"radar worker"*)
    if [ -e /.dockerenv ] && ! python -c "import socket; s=socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)); s.close()" 2>/dev/null; then
      echo "[entrypoint] INFO: no CAP_NET_RAW — ksubdomain will use DNS fallback (compose: cap_add NET_RAW for native)" >&2
    fi
    ;;
esac

python -c "from radar.engine.version import apply_engine_dropin; w=apply_engine_dropin();
print('[entrypoint] engine drop-in:', ', '.join(w[:30]) if w else '(none)', flush=True)" || true

# pull + compose up 即可用：空库 create_all+stamp；已有库 alembic upgrade
if ! python /app/scripts/docker_db_init.py; then
  echo "[entrypoint] db-init failed" >&2
  exit 1
fi

exec "$@"
