# 阶段 O 占位：壳 + so 槽位（开核 P4 由 CI 注入 so；本文件不复制不存在的 so）
# 禁止：ARG/ENV 传入 GitHub PAT；禁止 COPY .env / 密钥

FROM python:3.12-slim-bookworm

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates unzip \
  && rm -rf /var/lib/apt/lists/*

ARG SUBFINDER_VERSION=2.7.0
RUN set -eux; \
  arch="$(uname -m)"; \
  case "$arch" in x86_64) sf_arch=amd64 ;; aarch64|arm64) sf_arch=arm64 ;; *) exit 1 ;; esac; \
  curl -fsSL \
    "https://github.com/projectdiscovery/subfinder/releases/download/v${SUBFINDER_VERSION}/subfinder_${SUBFINDER_VERSION}_linux_${sf_arch}.zip" \
    -o /tmp/sf.zip \
  && unzip -o /tmp/sf.zip -d /usr/local/bin subfinder \
  && chmod +x /usr/local/bin/subfinder \
  && rm -f /tmp/sf.zip

WORKDIR /app
COPY pyproject.toml README.md ./
COPY src ./src
COPY migrations ./migrations
COPY alembic.ini ./
RUN pip install --no-cache-dir -e .

# 约定：CI 在构建前将 radar_engine*.so 放入 build context 根目录并取消下一行注释
# COPY radar_engine*.so /app/

ENV PATH="/usr/local/bin:${PATH}"
EXPOSE 8000
CMD ["uvicorn", "radar.server.app:app", "--host", "0.0.0.0", "--port", "8000"]
