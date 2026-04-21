# MyActions — 多仓库 Docker 镜像构建推送

GitHub Actions workflow，支持多架构构建并推送到多个容器镜像仓库。

## 支持的镜像仓库

| 仓库 | 地址 | 推送方式 |
|------|------|----------|
| GHCR | `ghcr.io` | 构建阶段直接推送 |
| 腾讯云 TCR | `ccr.ccs.tencentyun.com` | 构建阶段直接推送 |
| Docker Hub | `docker.io` | skopeo 从 GHCR 同步 |
| 阿里云 ACR | 自定义 | skopeo 从 GHCR 同步 |
| 华为云 SWR | 自定义 | skopeo 从 GHCR 同步 |
| 腾讯云 CNB | 自定义 | skopeo 从 GHCR 同步 |

## 架构支持

- `amd64`
- `arm64`

构建完成后自动创建多架构 manifest，拉取时自动匹配当前平台。

## 使用方式

### 1. 配置 `image-config.yaml`

```yaml
image_name: cloud-browser-slim
tags: latest,v1.0
```

### 2. 配置 Secrets / Variables

在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置：

| 类型 | 名称 | 用途 |
|------|------|------|
| — | `GITHUB_TOKEN` | 自动提供，GHCR 推送 |
| Variable | `DOCKERHUB_NAMESPACE` | Docker Hub 命名空间 |
| Variable | `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| Secret | `DOCKERHUB_TOKEN` | Docker Hub Access Token |
| Variable | `TCR_USERNAME` | 腾讯云 TCR 用户名 |
| Variable | `TCR_NAMESPACE` | 腾讯云 TCR 命名空间 |
| Secret | `TCR_PASSWORD` | 腾讯云 TCR 密码 |
| Variable | `ALIYUN_REGISTRY` | 阿里云 ACR 地址 |
| Variable | `ALIYUN_NAMESPACE` | 阿里云 ACR 命名空间 |
| Variable | `ALIYUN_REGISTRY_USERNAME` | 阿里云 ACR 用户名 |
| Secret | `ALIYUN_REGISTRY_PASSWORD` | 阿里云 ACR 密码 |
| Variable | `HUAWEI_REGISTRY` | 华为云 SWR 地址 |
| Variable | `HUAWEI_NAMESPACE` | 华为云 SWR 命名空间 |
| Variable | `HUAWEI_REGISTRY_USERNAME` | 华为云 SWR 用户名 |
| Secret | `HUAWEI_REGISTRY_PASSWORD` | 华为云 SWR 密码 |
| Variable | `TENCENT_REGISTRY` | 腾讯云 CNB 地址 |
| Variable | `TENCENT_NAMESPACE` | 腾讯云 CNB 命名空间 |
| Variable | `TENCENT_REGISTRY_USERNAME` | 腾讯云 CNB 用户名 |
| Secret | `TENCENT_REGISTRY_PASSWORD` | 腾讯云 CNB 密码 |

### 3. 触发构建

进入 Actions → Build and Push Docker Image → Run workflow，勾选目标仓库即可。

也可通过 `dockerfile_url` 参数指定远程 Dockerfile 地址。

## Workflow 流程

```
prepare → build (amd64 + arm64 并行) → merge (多架构 manifest)
                                         ↓
                              sync-aliyun (可选)
                              sync-huawei (可选)
                              sync-tencent-cnb (可选)
                              sync-dockerhub (可选)
                                         ↓
                              cleanup-ghcr (未勾选 GHCR 时清理)
```

- **GHCR / TCR**：在 build 阶段直接推送，速度快
- **其他仓库**：构建完成后通过 skopeo 从 GHCR 同步，支持 `--all` 多架构复制
