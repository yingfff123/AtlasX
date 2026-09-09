#!/usr/bin/env bash
# 检测 Debian 系（含 Kali / Ubuntu）
set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
  echo "[detect-os] 无法读取 /etc/os-release" >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

id_l="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"
like_l="$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"

if [[ "$id_l" == "debian" || "$id_l" == "ubuntu" || "$id_l" == "kali" ]] \
  || [[ "$like_l" == *debian* ]]; then
  echo "$id_l"
  exit 0
fi

echo "[detect-os] 不支持的系统: ID=${ID:-?} ID_LIKE=${ID_LIKE:-?}" >&2
echo "[detect-os] 首版仅支持 Debian / Ubuntu / Kali" >&2
exit 1
