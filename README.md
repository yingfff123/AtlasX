# AtlasX

<img width="1280" height="369" alt="0" src="https://github.com/user-attachments/assets/afab0f77-5d81-4702-b04e-bbe45f95002d" />

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/)
[![Docker](https://img.shields.io/badge/deploy-Docker-2496ED.svg)](https://github.com/yingfff123/AtlasX)
[![Release](https://img.shields.io/badge/release-v0.2.8-brightgreen.svg)](https://github.com/yingfff123/AtlasX)

**企业暴露面收集与持续监控 —— 自托管 ASM。**

录入企业与根域后，从证书透明、测绘、被动 DNS、搜索与可选主动探测等多路汇总资产，做存活 / 指纹 / 路径发现与风险线索，并保留跨轮变更。数据落本机 PostgreSQL；测绘与 LLM 密钥全部自配，不内置第三方 key。

不是漏洞扫描器，也不内置 PoC。暴露面收齐、排好序、证据留在库里；后续交给 Yakit / Burp / 自己。

---

## 能力

- **多源采集（30+）**：证书透明、被动 DNS、国内外测绘、搜索引擎、代码泄露、备案 / Whois 等；未配 key 的源自动跳过
- **零 key 首扫**：crt.sh + subfinder 即可出资产树；FOFA / Quake / Shodan 等在设置页配置后即用
- **主动 / 被动分离**：ksubdomain、OneForAll 爆破需显式勾选
- **泛解析去噪**、多源置信度、存活 / 指纹 / 路径 / JS 线索
- **变更与关联**：跨轮 diff；同 IP / 证书 / 指纹聚合
- **运营台**：企业 / 项目 / 扫描 / 资产树 / RBAC；断点续扫
- **可选 LLM**：未配置时规则底档仍可用

| 能力 | CE | Pro |
|---|:---:|:---:|
| 多源采集 · 去噪佐证 · 变更监控 | ✅ | ✅ |
| 资产树 / 关联 / 基础风险定级 | ✅ | ✅ |
| 深挖验证（Deep Dive） | ❌ | ✅ |
| 网关配方 / 栈识别抬档 | ❌ | ✅ |
| 深 LLM 证据归类 | ❌ | ✅ |
| 查询 API | ❌ | ✅ |
| docx 威胁报告 | ❌ | ✅ |
| 授权 | MIT 自部署 | 商业 License |

未激活 License 时按 CE 使用；**设置 → 系统** 粘贴 License 解锁 Pro。采集源不按许可阉割。

---

## 快速开始

- 系统：Linux **amd64** 或 **arm64**（含 Mac Apple Silicon + Docker Desktop）
- Docker Compose v2；建议 ≥ 2C / 2G（磁盘 ≥ 20G）
- `setup.sh` 按架构拉镜像：`0.2.8`（amd64）或 `0.2.8-arm64`

```bash
git clone https://github.com/yingfff123/AtlasX.git && cd AtlasX && bash setup.sh
```

国内 `git clone` 不通时：

```bash
rm -rf AtlasX && mkdir AtlasX && cd AtlasX \
  && curl -fL --progress-bar https://codeload.github.com/yingfff123/AtlasX/tar.gz/refs/heads/main \
     | tar xz --strip-components=1 \
  && bash setup.sh
```

终端会打印访问地址与 `RADAR_ACCESS_TOKEN`。打开 `http://<主机>:8000/`。

| 用户名 | 初始密码 |
|--------|----------|
| `adminx` | `Atlasx123!@#` |

登录后立刻改密。脚本 / API 使用请求头 `Authorization: Bearer <RADAR_ACCESS_TOKEN>`（不再支持 URL `?token=`）。

### 界面预览

登录界面

<img width="2832" height="1458" alt="image" src="https://github.com/user-attachments/assets/1b36fd38-8815-4267-a2ad-d403dd74f228" />

总览

<img width="3024" height="1542" alt="image" src="https://github.com/user-attachments/assets/2b66ce82-4e14-4fb5-963d-796d37b76021" />

资产详情

<img width="2956" height="1518" alt="image" src="https://github.com/user-attachments/assets/2c793169-f554-4c3f-bdb7-c4e53c470697" />

---

## 使用

1. 登录并修改默认密码
2. 设置里按需填测绘 / 搜索 / LLM 凭据（也可先免 key 首扫）
3. 创建企业、录入根域、发起扫描；主动爆破仅在需要时勾选
4. 在资产台跟进存活、指纹、路径、关联与变更；需要时激活 Pro
5. 升级：`bash update.sh`（默认保留数据）

也可在 **设置 → 系统** 检查更新（[AtlasX-updates](https://github.com/yingfff123/AtlasX-updates)）。

清空后重装：

```bash
docker compose down -v && docker compose pull && docker compose up -d
```

---

## 架构

<img width="2178" height="994" alt="ScreenShot_2026-09-08_233353_914" src="https://github.com/user-attachments/assets/a9dc9cf9-968d-4319-8f70-5bdf23046c8f" />

```text
根域 → 多源采集 → 归一 / 去噪 / 泛解析 → append-only 存储
     → 投影成资产 → 存活 / 指纹 / 路径 / JS → 风险 · 关联 · 变更
     → Web（+ Pro：深挖 · 查询 API · 威胁报告）
```

| 组件 | 说明 |
|------|------|
| **Web** | FastAPI + Jinja2 + HTMX |
| **Worker** | 采集与富化（`NET_RAW`/`NET_ADMIN` 可选；无权限时 DNS 回退） |
| **数据库** | PostgreSQL |

---

## 安全

- Token / API Key 只放本机 `.env` 或系统设置
- 不要把数据库端口映射到公网
- 8000 对公网开放时用强 `RADAR_ACCESS_TOKEN`，并立刻改默认管理员密码
- 主动爆破仅对已授权资产开启

---

## 链接

| 资源 | 地址 |
|------|------|
| 本仓库 | https://github.com/yingfff123/AtlasX |
| 镜像 | amd64：`atlasx-docker:0.2.8`；arm64：`atlasx-docker:0.2.8-arm64`（国内默认 `ghcr.1ms.run`） |
| 更新通道 | https://github.com/yingfff123/AtlasX-updates |

---

## 鸣谢

| 项目 | 作者 / 组织 | 用途 |
|------|-------------|------|
| [OneForAll](https://github.com/shmilylty/OneForAll) | [@shmilylty](https://github.com/shmilylty) | 子域聚合与爆破 |
| [ksubdomain](https://github.com/boy-hack/ksubdomain) | [@boy-hack](https://github.com/boy-hack) | DNS 主动枚举 |
| [subfinder](https://github.com/projectdiscovery/subfinder) | [@projectdiscovery](https://github.com/projectdiscovery) | 被动子域 |
| [Sublist3r](https://github.com/aboul3la/Sublist3r) | [@aboul3la](https://github.com/aboul3la) | 搜索引擎子域 |
| [massdns](https://github.com/blechschmidt/massdns) | [@blechschmidt](https://github.com/blechschmidt) | DNS 解析（OneForAll） |
| [MUKI](https://github.com/yingfff123/MUKI) | [@yingfff123](https://github.com/yingfff123) | 指纹与路径规则 |
| [veo](https://github.com/neouks/veo) | [@neouks](https://github.com/neouks) | Web 指纹 |
| [FastAPI](https://github.com/fastapi/fastapi) / [HTMX](https://github.com/bigskysoftware/htmx) / [SQLAlchemy](https://github.com/sqlalchemy/sqlalchemy) / [httpx](https://github.com/encode/httpx) | — | Web 与数据底座 |

以及 crt.sh、HackerTarget、OTX 与各测绘平台开放 API。

---

## 免责声明

仅供**已获合法授权**的安全评估、资产管理与防御研究使用。

1. 使用者须确认目标在授权范围内；不得对未授权系统开展采集或扫描。
2. 应遵守适用法律法规；超范围使用后果自负。
3. 输出为技术参考，「现象」不等于已验证漏洞，须人工复核。
4. 软件按「现状」提供；作者不对使用或无法使用所致损失承担责任。
5. 请勿信任来源不明的第三方修改包。

使用即视为同意；不同意请停止使用并卸载。
