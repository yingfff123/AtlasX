# AtlasX-docker

Debian / Kali / Ubuntu 一键部署 AtlasX（灯塔式 compose）。

设计说明见主仓：`AtlasX/docs/superpowers/specs/2026-09-05-linux-docker-kali-design.md`（v2）。

## 现在怎么装（MVP）

同级目录：

```text
父目录/
  AtlasX/           # 主仓源码
  AtlasX-docker/    # 本仓库
```

```bash
cd AtlasX-docker
chmod +x setup.sh update.sh scripts/*.sh
bash setup.sh          # 需要 Docker；没有则 sudo bash scripts/install-docker.sh
```

默认生成带随机 `RADAR_ACCESS_TOKEN` 的 `.env`（权限 600）。访问：

```text
http://<IP>:8000/?token=<token>
# 或 Header: Authorization: Bearer <token>
```

升级（保留数据库 volume）：

```bash
bash update.sh
```

## 开核发版后（阶段 O）

`.env` 中设：

```bash
ATLASX_RELEASE=1
ATLASX_IMAGE=ghcr.io/yingfff123/atlasx
ATLASX_IMAGE_TAG=latest
```

再 `bash setup.sh` / `update.sh`（pull 镜像，无需旁路源码）。

## 安全（必读）

- **不要**把 GitHub PAT、`.env`、MASTER_KEY 写进 Dockerfile / compose / 镜像。
- PAT 只放在宿主机环境或 GitHub Actions **Secrets**（本仓已用 `GHCR_TOKEN` 名）。
- Postgres 不映射到宿主机；公网务必改默认管理员密码。
- 国内拉 Docker Hub / ghcr 慢时，自行配置 registry mirror（脚本不自动改源）。

## 仓库

- 部署仓：https://github.com/yingfff123/AtlasX-docker
- 镜像（发版后）：`ghcr.io/yingfff123/atlasx`
