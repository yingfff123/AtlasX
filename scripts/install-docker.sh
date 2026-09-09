#!/usr/bin/env bash
# apt 安装 Docker + compose（Debian / Kali / Ubuntu）
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    echo "[install-docker] 已存在 Docker + compose"
    exit 0
  fi
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[install-docker] 需要 root：请用 sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends docker.io curl ca-certificates

# compose plugin 或独立包（Kali/Debian 包名可能不同）
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-v2 \
    || apt-get install -y --no-install-recommends docker-compose \
    || true
fi

systemctl enable --now docker 2>/dev/null || service docker start || true

if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
  echo "[install-docker] 未能安装 compose，请手工安装 docker compose plugin" >&2
  exit 1
fi

echo "[install-docker] 完成"
