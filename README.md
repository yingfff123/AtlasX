# AtlasX Docker

AtlasX 的 **Linux / Docker 一键部署仓**。面向企业暴露面收集（ASM）：多源子域与测绘采集 → 存活 / 指纹 / 路径富化 → 风险与作业台，数据落在本机 Postgres volume。

> 本仓只提供 **compose、安装脚本与发版镜像引用**。业务核心以护源镜像交付（`:secure` 内 Nuitka `.so`），**不包含**私有主仓明文核心源码。

```text
http://<主机>:8000/?token=<RADAR_ACCESS_TOKEN>
```

## 核心能力

- **一键拉起**：`setup.sh` 生成 `.env`、拉取 GHCR 镜像、启动 db / web / worker；空库由容器入口自动 `create_all` + stamp，无需手工 migrate。
- **采集与富化**：镜像内含 Linux 工具链（subfinder、ksubdomain、sublist3r、OneForAll、veo 等）；采集器按 Credential 对接 FOFA / Shodan 等测绘与被动源。
- **Web + Worker**：UI / API 与扫描队列分离；重启不丢库（`atlasx_pgdata`），引擎热更落独立 volume。
- **开核发行**：`secure` 护源镜像 + 可选 License 解锁 Pro；`ce` 为 Community 裁剪构建。
- **可升级**：换镜像 tag 做整包升级；引擎 `.so` 包走公开更新通道 [AtlasX-updates](https://github.com/yingfff123/AtlasX-updates)。

## 快速开始

### 环境要求

- Linux（Debian / Ubuntu / Kali 等）
- Docker + Docker Compose v2
- 出网拉取 `ghcr.io`（镜像已公开，一般无需登录）

### 一条命令安装

```bash
git clone https://github.com/yingfff123/AtlasX-docker.git && cd AtlasX-docker && bash setup.sh
```

安装完成后终端会打印访问地址。用 `.env` 中的 `RADAR_ACCESS_TOKEN` 打开：

```text
http://<主机>:8000/?token=<RADAR_ACCESS_TOKEN>
```

默认管理员（首次启动自动引导，**登录后请立刻改密**）：

| 用户名 | 初始密码 |
|--------|----------|
| `adminx` | `Atlasx123!@#` |

### 镜像拉取（可选）

```bash
docker pull ghcr.io/yingfff123/atlasx-docker:secure   # 推荐
docker pull ghcr.io/yingfff123/atlasx-docker:ce
docker pull ghcr.io/yingfff123/atlasx-docker:latest   # 同 secure
```

## 基本工作流

1. `setup.sh` 拉起栈，用 token 打开 Web，登录并修改默认密码。
2. 在设置中按需配置测绘 / LLM 等 Credential。
3. 创建企业或项目，录入根域，发起扫描（被动采集默认开启；主动爆破需显式勾选）。
4. 在资产台查看存活、指纹（veo）、路径与风险摘要；Pro License 解锁深挖 / 报告等能力。
5. 日常升级：`bash update.sh`（保留数据库 volume）。

## 镜像标签

| Tag | 说明 |
|-----|------|
| `secure` | **推荐**。护源发行；含 Pro 实现 so，功能仍由 License 门闸 |
| `ce` | Community：构建前 strip Pro 实现 |
| `latest` | 指向当前 `secure` |
| `mvp` | 全源过渡镜像，仅开发自建，勿当护源验收 |

`.env` 中设置：

```bash
ATLASX_RELEASE=1
ATLASX_IMAGE=ghcr.io/yingfff123/atlasx-docker
ATLASX_IMAGE_TAG=secure
```

## 架构

```text
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│  Browser    │────▶│  web         │────▶│  Postgres      │
│  :8000      │     │  (FastAPI)   │     │  atlasx_pgdata │
└─────────────┘     └──────┬───────┘     └────────────────┘
                           │ enqueue
                           ▼
                    ┌──────────────┐
                    │  worker      │  采集 / 富化 / 队列
                    │  (radar)     │
                    └──────────────┘
                           │
              volumes: atlasx_engine / atlasx_updates
```

| 组件 | 职责 |
|------|------|
| **db** | Postgres 16；库表由 web/worker 入口自动初始化 |
| **web** | UI、鉴权、扫描编排 API |
| **worker** | 后台扫描与富化（与 web 共用镜像） |

容器启动顺序：`db` healthy → entrypoint 做 **db-init** → 再启动业务进程。可用 `ATLASX_SKIP_DB_INIT=1` 跳过（一般不需要）。

## 升级

```bash
cd AtlasX-docker
bash update.sh
```

- **整包 / 壳升级**：改 `ATLASX_IMAGE_TAG` 后 `update.sh`（或 `docker compose pull && up -d`）。
- **仅引擎 so**：见 [AtlasX-updates](https://github.com/yingfff123/AtlasX-updates)，写入 `atlasx_engine` volume。

数据默认保留在 `atlasx_pgdata`。若要空库重来：

```bash
docker compose down -v
docker compose pull
docker compose up -d
```

## 开发：旁路源码构建

同级放置私有主仓 `AtlasX-clean/`（或 `AtlasX/`），然后：

```bash
# .env
ATLASX_RELEASE=0
# setup.sh 会写入 ATLASX_ROOT / ATLASX_DOCKER_ROOT
bash setup.sh
```

在构建机推送护源镜像（建议 tmux）：

```bash
export ATLASX_ROOT=/path/to/AtlasX-clean
echo "$GHCR_TOKEN" | docker login ghcr.io -u USER --password-stdin
bash scripts/build-and-push-secure.sh
```

**禁止**把 macOS 的 `tools/bin` 打进镜像；工具须在 Linux 构建阶段安装。

## 安全建议

- 密钥与 token **只放主机 `.env`**，勿提交 git、勿 bake 进镜像。
- Postgres **不要**映射到公网；公网暴露 8000 时使用强 `RADAR_ACCESS_TOKEN`。
- 首次登录后立即修改 `adminx` 密码。
- Classic PAT / `write:packages` 仅用于推镜像的维护者机器，用完轮换。

## 仓库结构

```text
AtlasX-docker/
  docker-compose.yml       # 发版：pull GHCR
  docker-compose.mvp.yml   # 开发：旁路主仓 build
  Dockerfile               # 护源多阶段（context = 主仓）
  setup.sh / update.sh     # 安装与升级
  scripts/                 # wait-db、构建推送等
  .env.example             # 无密钥；setup 生成正式 .env
```

## 相关链接

| 资源 | 说明 |
|------|------|
| 本仓 | https://github.com/yingfff123/AtlasX-docker |
| 镜像 | `ghcr.io/yingfff123/atlasx-docker` |
| 更新通道 | https://github.com/yingfff123/AtlasX-updates |

---

仅在已获授权的资产范围内使用。滥用采集与扫描能力可能违法。
