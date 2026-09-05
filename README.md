# AtlasX Docker

**一键在 Linux 上部署 AtlasX（企业暴露面雷达）。**

Postgres + Web + Worker，一条 `setup.sh` 起全栈。面向 Debian / Ubuntu / Kali 等常见发行版；数据落在 Docker volume，升级不丢库。

```text
http://<主机>:8000/?token=<RADAR_ACCESS_TOKEN>
```

---

## 你需要什么

| 项 | 说明 |
|----|------|
| Docker + Compose v2 | 没有则可执行 `sudo bash scripts/install-docker.sh` |
| 开放端口 | 默认 `8000`（可在 `.env` 改 `ATLASX_HTTP_PORT`） |
| 磁盘 | 镜像 + Postgres 数据；建议预留数 GB |

**不要**把 GitHub Token、`.env`、`MASTER_KEY` 写进 Dockerfile 或提交进仓库。

---

## 两种安装方式

### 方式一：拉镜像（推荐）

不依赖本机源码，适合服务器与日常升级。

```bash
git clone https://github.com/yingfff123/AtlasX-docker.git
cd AtlasX-docker
chmod +x setup.sh update.sh scripts/*.sh
```

编辑 `.env`（首次可先跑 `setup.sh` 自动生成，再改）：

```bash
ATLASX_RELEASE=1
ATLASX_IMAGE=ghcr.io/yingfff123/atlasx-docker
ATLASX_IMAGE_TAG=mvp          # 过渡全源；开核发版后改用 secure
```

```bash
bash setup.sh
```

镜像：

```bash
docker pull ghcr.io/yingfff123/atlasx-docker:mvp
# 开核护源镜像就绪后：
# docker pull ghcr.io/yingfff123/atlasx-docker:secure
```

若 Packages 仍为 Private，到 GitHub Packages 将该容器包设为 **Public** 后再匿名 pull。

### 方式二：旁路源码构建（开发 / 定制）

将 AtlasX **应用源码仓**与本仓放在同级目录：

```text
父目录/
├── AtlasX/            # 应用源码（旁路主仓）
└── AtlasX-docker/     # 本仓库
```

```bash
cd AtlasX-docker
# .env 中 ATLASX_RELEASE=0（或不设），setup 会写入 ATLASX_ROOT
bash setup.sh
```

将使用 `docker-compose.mvp.yml`，以 `Dockerfile.mvp` 从旁路 `AtlasX` 构建 `atlasx:mvp`。

---

## 升级

```bash
bash update.sh
```

- 保留 Postgres 数据卷 `atlasx_pgdata`
- **不会**覆盖已有 `RADAR_ACCESS_TOKEN` / `MASTER_KEY`
- `ATLASX_RELEASE=1` 时：`pull` 新镜像 tag 后重启并跑迁移
- `ATLASX_RELEASE=0` 时：按旁路源码重新 `build`

### 双通道（开核发版后）

| 通道 | 改什么 | 怎么做 |
|------|--------|--------|
| **镜像** | 壳 + 内置引擎 | 改 `ATLASX_IMAGE_TAG` → `./update.sh` |
| **引擎包** | 仅算法 `.so` | Web「系统」页上传引擎升级包；写入 volume `atlasx_engine`，换镜像也不丢 |

护源编译、验收与升级细节见旁路主仓文档：

`AtlasX/docs/superpowers/specs/2026-09-06-open-core-protect-and-upgrade.md`

本地构建开核镜像：

```bash
export ATLASX_ROOT=/path/to/AtlasX
docker build -f Dockerfile -t ghcr.io/yingfff123/atlasx-docker:secure "$ATLASX_ROOT"
```

> `:mvp` 含完整 Python 源码，仅作过渡。护源验收请用 `:secure`（无核心算法 `.py`）。

---

## 访问与安全

`setup.sh` 默认生成随机 `RADAR_ACCESS_TOKEN`（`.env` 权限 `600`）。

| 方式 | 示例 |
|------|------|
| Query | `http://IP:8000/?token=<token>` |
| Header | `Authorization: Bearer <token>` |

务必做到：

1. 首次登录后**立即修改**默认管理员密码  
2. Postgres **不**映射到宿主机公网端口（compose 已按此设计）  
3. 公网部署务必保留强 token / 登录，勿裸奔  
4. 密钥只放宿主机 `.env` 或 CI Secrets，**永不进镜像**

---

## 仓库里有什么

| 文件 | 作用 |
|------|------|
| `setup.sh` | 检测环境、写 `.env`、拉起栈 |
| `update.sh` | 升级镜像或重建，保留数据卷 |
| `docker-compose.yml` | 发版模式（pull + 引擎热更卷） |
| `docker-compose.mvp.yml` | 源码构建模式 |
| `Dockerfile` | 开核多阶段构建（Nuitka → `.so`） |
| `Dockerfile.mvp` | 全源过渡镜像 |
| `scripts/` | 装 Docker、等库就绪等辅助脚本 |

服务组成：`db`（Postgres 16）· `web`（API/UI）· `worker`（扫描队列）。

---

## 一键更新（升级包）

升级包放在公开仓 **[AtlasX-updates](https://github.com/yingfff123/AtlasX-updates)**（本仓若为 Private，匿名读不到 channel）。

| 用途 | 链接 |
|------|------|
| 检查更新通道 | https://raw.githubusercontent.com/yingfff123/AtlasX-updates/main/channel.json |
| 最新包（资源名 `atlasx-upgrade.zip`） | https://github.com/yingfff123/AtlasX-updates/releases/latest/download/atlasx-upgrade.zip |
| Releases | https://github.com/yingfff123/AtlasX-updates/releases |

`.env` 配置 `RADAR_UPDATE_CHANNEL_URL` 为上表通道后，在 Web **设置 → 系统 → 检查更新** 即可。

---

## 链接

| | |
|--|--|
| 部署仓 | https://github.com/yingfff123/AtlasX-docker |
| 升级仓 | https://github.com/yingfff123/AtlasX-updates |
| 容器镜像 | [`ghcr.io/yingfff123/atlasx-docker`](https://github.com/users/yingfff123/packages/container/package/atlasx-docker) |

---

## License

与 AtlasX 主项目一致（MIT）。
