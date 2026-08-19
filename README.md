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

也可通过 `dockerfile_url` 参数指定远程 Dockerfile 地址，或通过 `git_repo_url` 直接构建远程 Git 仓库中的 Dockerfile：

- **完整克隆**（保留全部提交历史与 tags，`--filter=blob:none` 减小传输）——部分项目（如 casdoor）构建时会用 go-git 读取 git 历史计算版本号，浅克隆会导致 `object not found` 构建失败。
- `git_repo_ref` 支持分支 / tag / commit，留空则使用仓库默认分支。
- `git_repo_path` 指定 Dockerfile 所在子目录，`build_context_path` 指定构建上下文根。

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

## Sync Docker Image（已有镜像分发到各仓库）

`Sync Docker Image` workflow 把**已存在的镜像**（任意公开源）直接同步/分发到目标仓库，无需构建。触发时选 `mode`：

| mode | 用途 | 输入 |
|------|------|------|
| `single`（默认） | 同步单个镜像 | `source_image` / `target_name` / `target_registry` |
| `batch` | 读文件批量同步 | `images_file` / `target_registry` / `min_free_gb` |

### 批量同步（batch）

1. 编辑仓库根的 [`sync-images.yaml`](./sync-images.yaml)，列出要同步的镜像：

```yaml
images:
  - source: nginx:1.25.3          # 纯字符串：tag 跟随源，目标名取最后一段
  - source: redis:7.2
    target: my-redis              # 对象写法：target 覆盖目标镜像名
  - source: ghcr.io/foo/bar:v1.2.0
    target: bar
    tag: stable                   # 可选：覆盖目标标签（retag），拉 v1.2.0 推 stable
```

2. Actions → Sync Docker Image → `mode=batch` → 选 `target_registry`（**整表共用一个仓库**）→ Run。

- **目标仓库**：整表唯一，由 `target_registry` 决定，文件里不写仓库。
- **磁盘管理**：镜像多时，每条同步前检查可用磁盘，低于 `min_free_gb`（默认 `5` GB）会自动清理 runner 临时空间（dotnet/android/ghc/boost 等预装大目录 + docker prune + skopeo tmp）。
- **容错**：源须公开可拉取；单条失败不中断整批，全部跑完后若有失败才标记失败，并在 Summary 输出逐条状态表。
- **支持的目标仓库**：Quay.io / 阿里云 ACR / 华为云 SWR / 腾讯云 CNB / Docker Hub / 腾讯云 TCR / GHCR（需在 Secrets/Variables 配好对应凭据，见 `SECRETS.md`；Quay 首次推送会自动建仓）。
