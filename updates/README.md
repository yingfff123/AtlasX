# 升级包发布说明（给维护者）

**不必另建 GitHub 仓库。** 升级包放在本仓 **Releases**，检查更新读本目录的 `channel.json`。

## 用户侧（一键更新）

1. 环境变量（或镜像 `.env`）：

```bash
RADAR_UPDATE_CHANNEL_URL=https://raw.githubusercontent.com/yingfff123/AtlasX/main/updates/channel.json
```

未配置时，应用默认查本仓 GitHub Releases（`yingfff123/AtlasX`）。

2. Web：**设置 → 系统 → 检查更新 → 下载升级包 → 应用**（需重启 web/worker）。

## 你每次发版怎么做

### A. 壳 / 应用升级包（zip）

1. 打好 zip（结构：`manifest.json` + `payload/...`，见主仓 `radar.update`）。
2. 建议资源名固定为 **`atlasx-upgrade.zip`**（方便 `releases/latest/download/...`），或带版本号再在 channel 里写死 URL。
3. 建 Release（tag 建议 `upgrade-0.2.5`）：

```bash
gh release create upgrade-0.2.5 ./dist/atlasx-upgrade.zip \
  --repo yingfff123/AtlasX \
  --title "Upgrade 0.2.5" \
  --notes "修复说明…"
```

4. 改 `updates/channel.json`：

```json
{
  "version": "0.2.5",
  "notes": "…",
  "download_url": "https://github.com/yingfff123/AtlasX/releases/download/upgrade-0.2.5/atlasx-upgrade.zip",
  "sha256": "<zip 的 sha256>"
}
```

5. 提交并 push `updates/channel.json`（或 API 更新该文件）。

### B. 仅引擎 `.so` 包

仍可用系统页手动上传；或另发 Release 资源 `atlasx-engine.zip`，另备 `channel-engine.json`（可选，当前 UI 默认读一个通道）。

### C. Docker 整镜像

与 zip 无关：改用户 `.env` 的 `ATLASX_IMAGE_TAG` 后执行 `./update.sh`。

## 固定链接（可写进文档 / 默认配置）

| 用途 | URL |
|------|-----|
| 检查更新通道 | `https://raw.githubusercontent.com/yingfff123/AtlasX/main/updates/channel.json` |
| 最新升级包（资源名固定时） | `https://github.com/yingfff123/AtlasX/releases/latest/download/atlasx-upgrade.zip` |
| Releases 列表 | `https://github.com/yingfff123/AtlasX/releases` |
