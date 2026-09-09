# AtlasX

<img width="1280" height="369" alt="0" src="https://github.com/user-attachments/assets/afab0f77-5d81-4702-b04e-bbe45f95002d" />

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/)
[![Docker](https://img.shields.io/badge/deploy-Docker-2496ED.svg)](https://github.com/yingfff123/AtlasX)
[![Release](https://img.shields.io/badge/release-v0.2.7.4-brightgreen.svg)](https://github.com/yingfff123/AtlasX)

**企业暴露面收集与持续监控 —— 自托管 ASM。**

录入企业与根域后，AtlasX 从证书透明、测绘引擎、被动 DNS、搜索与可选主动探测等多路汇总影子资产，整理成可归属的资产库；完成存活探测、指纹识别与路径发现，并给出可解释的风险线索与跨轮变更对照。数据落本机 PostgreSQL，测绘 / LLM 密钥全部自配，系统不内置任何第三方密钥。

> 市面上不缺子域名收集工具。缺的是：扫完之后，这条资产从哪来、靠不靠谱、今晚值不值得开 Yakit——以及企业侧「我们到底暴露了什么、什么时候变的」。

---

## 为什么要做

子域工具往往只给一张扁平清单。AtlasX 面向实战作业台：

| 痛点 | AtlasX 怎么做 |
|------|----------------|
| 扫完一堆孤立子域 | **连得起来** — 带来源、置信度、归属到企业 / 项目，可与历史扫描对照 |
| 黑盒分数说不清今晚打哪 | **看得懂** — 多源佐证信号条 + 规则底档风险分级，结论可解释 |
| 算法一改就要重扫 | **跟得住** — 原始发现 append-only，投影游标增量消费，历史可重放 |
| 数据在别人 SaaS 上 | **信得过** — 私有化部署，凭据 Fernet 加密入库，密钥自管 |

它**不是**漏洞扫描器，也不内置 PoC 框架。它把暴露面收干净、排好序、把证据链留在库里——后半段交给 Yakit、Burp、你的 Agent 和你自己的手。

---

## 核心能力

- **多源采集（30+）**：证书透明、被动 DNS、国内外测绘、搜索引擎、代码泄露、备案 / Whois 等；没配 key 的源自动跳过，单源失败不中断主流程
- **零 key 首扫**：crt.sh + subfinder 即可出资产树；FOFA / Quake / Shodan / Censys / Chaos / ZoomEye / Hunter 等在设置页配置后即用
- **主动 / 被动分离**：ksubdomain、OneForAll 爆破需显式勾选，避免误扫面过大
- **泛解析与去噪**：权威 NS 随机名直查确认泛解析并折叠杂波；CDN 多解析剧本照常入库
- **多源佐证置信度**：独立来源累加、封顶 5 格信号条——不是黑盒分数
- **富化与作业**：存活、标题 / 栈指纹、路径与 JS 接口线索写入资产详情；tonight / soon / later 优先级
- **变更与关联**：跨轮 diff；同 IP / 证书 / 指纹自动聚合
- **运营台**：企业 / 项目 / 扫描 / 资产树 / 变更 / 多用户 RBAC；断点续扫、崩溃租约回收
- **可选 LLM**：辅助理解与预筛，默认不强制；没配模型时规则底档仍完整可用

### 版本能力

| 核心能力 | 社区版 CE | Pro 版 |
|---|:---:|:---:|
| 多源采集 · 去噪佐证 · 变更监控 | ✅ | ✅ |
| 资产树 / 关联分析 / 基础风险定级 | ✅ | ✅ |
| 深挖验证（Deep Dive + 现象分级） | ❌ | ✅ |
| 网关配方库 / 栈识别抬档 | ❌ | ✅ |
| 深 LLM 证据归类 | ❌ | ✅ |
| 查询 API | ❌ | ✅ |
| docx 威胁报告导出 | ❌ | ✅ |
| 授权与部署 | MIT 开源自部署 | 商业 License |


未激活 License 时按社区版（CE）使用；在 **设置 → 系统** 粘贴 License 后一次解锁全部 Pro 能力（深挖验证、网关配方、查询 API、docx 威胁报告等）。**采集源不按许可阉割**——有 key、有工具就跑。

---

## 快速开始

### 环境要求

- 系统：Linux（Debian / Ubuntu / Kali 等）
- 软件：Docker 与 Docker Compose v2，可访问 `ghcr.io`
- **最低配置：2 核 CPU / 2 GB 内存**（建议磁盘 ≥ 20 GB；资产与并发较多时建议 8 GB+）

### 一键安装

```bash
git clone https://github.com/yingfff123/AtlasX.git && cd AtlasX && bash setup.sh
```
```
curl -fsSL https://codeload.github.com/yingfff123/AtlasX/tar.gz/refs/heads/main | tar xz --strip-components=1 && bash setup.sh
```

安装结束后，终端会打印访问地址与 `.env` 中生成的 `RADAR_ACCESS_TOKEN`。浏览器打开：

```text
http://<主机>:8000/
```

首次登录账号（**登录后请立刻修改密码**）：

| 用户名 | 初始密码 |
|--------|----------|
| `adminx` | `Atlasx123!@#` |

> 机器入口 / 脚本调用可使用请求头 `Authorization: Bearer <RADAR_ACCESS_TOKEN>`（已不再支持 URL `?token=`，避免 Referer / 访问日志泄露）。

### 界面预览

登录界面

<img width="2832" height="1458" alt="image" src="https://github.com/user-attachments/assets/1b36fd38-8815-4267-a2ad-d403dd74f228" />

总览

<img width="3024" height="1542" alt="image" src="https://github.com/user-attachments/assets/2b66ce82-4e14-4fb5-963d-796d37b76021" />

资产详情

<img width="2956" height="1518" alt="image" src="https://github.com/user-attachments/assets/2c793169-f554-4c3f-bdb7-c4e53c470697" />

---

## 使用流程

1. 打开 Web，登录并修改默认密码。
2. 在设置中按需填写测绘、搜索或 LLM 凭据（也可先用免 key 源完成第一次扫描）。
3. 创建企业，录入根域，发起扫描；主动爆破类选项仅在需要时勾选。
4. 在资产台查看存活、指纹、路径与风险，结合关联与变更持续跟进；需要时激活 Pro。
5. 日常升级执行 `bash update.sh`（默认保留已有数据）。

---

## 架构

<img width="2178" height="994" alt="ScreenShot_2026-09-08_233353_914" src="https://github.com/user-attachments/assets/a9dc9cf9-968d-4319-8f70-5bdf23046c8f" />

```text
根域 → 多源采集 → 归一 / 去噪 / 泛解析闸 → append-only 存储
     → 投影成资产 → 存活 / 指纹 / 路径 / JS → 风险分级 · 关联 · 变更
     → Web 运营台（+ Pro：深挖作业单 · 查询 API · 威胁报告）
```

| 组件 | 说明 |
|------|------|
| **Web** | FastAPI + Jinja2 + HTMX；登录鉴权、扫描编排与设置 |
| **Worker** | 后台采集与富化（默认 `cap_add: NET_RAW/NET_ADMIN` 以跑原生 ksubdomain；无权限时自动 DNS 回退） |
| **数据库** | PostgreSQL；资产与扫描结果持久化（安装时自动初始化） |

采集层是唯一出网口，存储层是唯一碰库层；Web 与 CLI 共用同一条 pipeline。单源失败跳过继续——收集类任务可用性优先。

---

## 与同类工具

| 能力 | 子域收集器 | 商业 ASM SaaS | AtlasX |
|------|:----------:|:-------------:|:-------:|
| 多源子域 / 测绘 | ✅ | ✅ | ✅（30+，key 自配） |
| 泛解析折叠 | 少见 | 少见 | ✅ |
| 可解释置信度 | ❌ | 黑盒分 | ✅ |
| append-only 可重放 | ❌ | ❌ | ✅ |
| 今晚打哪 / 变更对照 | ❌ | 告警工单 | ✅ |
| 数据归属 | 本地文件 | 平台侧 | 私有化 |
| 部署 | CLI | 付费云 | Docker 一键 |

---

## 升级与数据

```bash
cd AtlasX
bash update.sh
```

- 应用与镜像升级：使用本仓库的 `update.sh`
- 也可在 **设置 → 系统** 检查更新（通道：[AtlasX-updates](https://github.com/yingfff123/AtlasX-updates)）

数据默认保留。若需清空后重装：

```bash
docker compose down -v
docker compose pull
docker compose up -d
```

---

## 安全建议

- 访问令牌与各类 API Key 只保存在主机 `.env` 或系统设置中，不要发到公开渠道
- 不要将数据库端口映射到公网；管理面优先绑内网 / VPN / SSH 隧道
- 若 8000 对公网开放：务必使用强 `RADAR_ACCESS_TOKEN`，并立刻修改默认管理员密码
- 主动爆破仅对已获授权资产开启；疑似越界（旁站、关联域）应停下确认

---

## 相关链接

| 资源 | 地址 |
|------|------|
| 本仓库 | https://github.com/yingfff123/AtlasX |
| 容器镜像 | `ghcr.io/yingfff123/atlasx-docker:0.2.7.4` |
| 更新通道 | https://github.com/yingfff123/AtlasX-updates |

创作不易，觉得好用可以点个 Star ⭐

---

## 免责声明

AtlasX 仅供**已获合法授权**的安全评估、资产管理与防御研究使用。

1. **授权边界**：使用者须自行确认目标资产在授权范围内；不得对未授权系统、第三方网络或无关组织开展采集、探测或扫描。
2. **合法合规**：使用者应遵守所在地及目标所属司法辖区的法律法规、行业规范与平台规则。因超范围使用、滥用扫描能力或由此产生的任何后果，由使用者自行承担。
3. **工具属性**：本软件提供的是暴露面发现与分析能力；输出的资产与风险信息均为技术参考，「现象」不等于已验证漏洞，须经人工复核后方可作为决策或对外提交依据。
4. **免责**：在法律允许的最大范围内，作者与维护者不对因使用或无法使用本软件而导致的直接或间接损失承担责任；软件按「现状」提供，不附带适销性、特定用途适用性等明示或默示担保。
5. **上游责任**：通过本仓库分发的镜像与更新通道仅用于官方发布物；请勿信任来源不明的第三方修改包。

使用本软件即视为已阅读并同意上述声明。若不同意，请立即停止使用并卸载相关组件。
