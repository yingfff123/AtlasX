#!/usr/bin/env bash
# 国内直连 ghcr.io 常极慢；优先南大 / 1ms 缓存，失败再回退官方。
# 由 setup.sh / update.sh source；需已定义 compose() 与 set_kv()。

atlasx_pull_release() {
  local tag="${ATLASX_IMAGE_TAG:-0.2.7.4}"
  local -a cands=()
  if [[ "${ATLASX_SKIP_MIRROR:-0}" != "1" ]]; then
    cands+=("ghcr.nju.edu.cn/yingfff123/atlasx-docker")
    cands+=("ghcr.1ms.run/yingfff123/atlasx-docker")
  fi
  cands+=("${ATLASX_IMAGE:-ghcr.io/yingfff123/atlasx-docker}")
  cands+=("ghcr.io/yingfff123/atlasx-docker")

  if [[ -z "${POSTGRES_IMAGE:-}" ]] || [[ "${POSTGRES_IMAGE}" == "postgres:16" ]]; then
    set_kv POSTGRES_IMAGE "docker.m.daocloud.io/library/postgres:16"
  fi

  local img seen=" "
  for img in "${cands[@]}"; do
    [[ -n "$img" ]] || continue
    [[ "$seen" == *" $img "* ]] && continue
    seen+=" $img "
    set_kv ATLASX_IMAGE "$img"
    # shellcheck disable=SC1091
    set -a; source .env; set +a
    echo "[pull] ${img}:${tag}  postgres=${POSTGRES_IMAGE}"
    if compose "$@" pull; then
      echo "[pull] ok ${img}:${tag}"
      return 0
    fi
    echo "[pull] ${img} 失败，换下一源…"
  done
  return 1
}
