#!/usr/bin/env bash
# 由 setup.sh / update.sh source；需已定义 set_kv()。
#
# 不用 `docker compose pull`：南大 ghcr.nju.edu.cn 对 /v2 与 manifest 秒回 200，
# 但 blobs 一直 0 字节，compose pull 不会失败、也不会换源，看起来像脚本卡死。
# 本地已有镜像则跳过；否则 `docker pull`（有层进度），1ms 优先，南大先探测层文件。

ATLASX_GHCR_NAME="yingfff123/atlasx-docker"

atlasx_has_image() {
  docker image inspect "$1" >/dev/null 2>&1
}

atlasx_retag_local() {
  local tag="$1" dest="$2"
  local src
  for src in \
    "${dest}:${tag}" \
    "atlasx:${tag}" \
    "ghcr.1ms.run/${ATLASX_GHCR_NAME}:${tag}" \
    "ghcr.io/${ATLASX_GHCR_NAME}:${tag}" \
    "ghcr.nju.edu.cn/${ATLASX_GHCR_NAME}:${tag}"; do
    if atlasx_has_image "$src"; then
      [[ "$src" == "${dest}:${tag}" ]] || docker tag "$src" "${dest}:${tag}"
      echo "$src"
      return 0
    fi
  done
  return 1
}

# 南大必须真能读到层；只通元数据会让 docker pull 挂死。
atlasx_nju_blobs_ok() {
  local tag="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$ATLASX_GHCR_NAME" "$tag" <<'PY'
import json, ssl, sys, urllib.request

name, tag = sys.argv[1], sys.argv[2]
ctx = ssl.create_default_context()
base = "https://ghcr.nju.edu.cn/v2/" + name
accept = (
    "application/vnd.oci.image.index.v1+json,"
    "application/vnd.oci.image.manifest.v1+json,"
    "application/vnd.docker.distribution.manifest.v2+json"
)

def load(url):
    req = urllib.request.Request(url, headers={"Accept": accept})
    with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
        return json.loads(resp.read())

try:
    doc = load(f"{base}/manifests/{tag}")
    if "manifests" in doc:
        doc = load(f"{base}/manifests/{doc['manifests'][0]['digest']}")
    digest = doc["layers"][0]["digest"]
    req = urllib.request.Request(
        f"{base}/blobs/{digest}",
        headers={"Range": "bytes=0-2047"},
    )
    with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
        if len(resp.read(64)) < 1:
            raise RuntimeError("empty")
except Exception:
    sys.exit(1)
PY
}

atlasx_pull_release() {
  local tag="${ATLASX_IMAGE_TAG:-0.2.7.4}"
  local repo="$ATLASX_GHCR_NAME"
  local dest="ghcr.1ms.run/${repo}"
  local found img ok=0
  local -a cands=()
  local seen=" "

  if [[ -z "${POSTGRES_IMAGE:-}" || "${POSTGRES_IMAGE}" == "postgres:16" ]]; then
    set_kv POSTGRES_IMAGE "docker.m.daocloud.io/library/postgres:16"
    set -a; source .env; set +a
  fi

  if found="$(atlasx_retag_local "$tag" "$dest")"; then
    set_kv ATLASX_IMAGE "$dest"
    set -a; source .env; set +a
    echo "[pull] 本地已有 ${found}，跳过 AtlasX 镜像下载"
  else
    if [[ "${ATLASX_SKIP_MIRROR:-0}" != "1" ]]; then
      cands+=("ghcr.1ms.run/${repo}")
      if atlasx_nju_blobs_ok "$tag"; then
        cands+=("ghcr.nju.edu.cn/${repo}")
      else
        echo "[pull] 跳过 ghcr.nju.edu.cn：能查清单，但层文件 0 字节（compose pull 会一直卡住）"
      fi
    fi
    cands+=("ghcr.io/${repo}")

    for img in "${cands[@]}"; do
      [[ -n "$img" ]] || continue
      [[ "$seen" == *" $img "* ]] && continue
      seen+=" $img "
      echo "[pull] docker pull ${img}:${tag}  （约 1.3GB，有层进度才算在动）"
      if docker pull "${img}:${tag}"; then
        dest="$img"
        ok=1
        break
      fi
      echo "[pull] ${img} 失败，换下一源…"
    done
    [[ "$ok" == "1" ]] || return 1
    set_kv ATLASX_IMAGE "$dest"
    set -a; source .env; set +a
  fi

  echo "[pull] postgres ${POSTGRES_IMAGE}"
  if ! atlasx_has_image "${POSTGRES_IMAGE}"; then
    docker pull "${POSTGRES_IMAGE}" || return 1
  fi
  echo "[pull] ok ${ATLASX_IMAGE}:${tag}"
  return 0
}
