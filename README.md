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

触发构建时通过 `platforms` 选择：`amd64+arm64`（默认，双架构并行构建）/ `amd64` / `arm64`。部分项目没有 arm64 支持，选单架构可避免无谓的失败构建。

构建完成后自动创建多架构 manifest，拉取时自动匹配当前平台。

### Build args

`build_args` 输入支持向 Dockerfile 传递构建参数，逗号分隔的 `KEY=VALUE`：

```
VERSION=1.2.3,DEBUG=false
```

## 使用方式

### 1. 配置 Secrets / Variables

在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置（按需，只配用到的仓库即可）：

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
| Variable | `QUAY_NAMESPACE` | Quay.io 命名空间 |
| Variable | `QUAY_USERNAME` | Quay.io 用户名 |
| Secret | `QUAY_PASSWORD` | Quay.io 密码（skopeo 推送用） |
| Secret | `QUAY_TOKEN` | Quay.io API Token（自动建仓用） |
| Variable | `RETENTION_AUTO_DELETE` | 设为 `true` 时，定时清理才会真实删除（见下文 GHCR Retention Cleanup） |

### 2. 触发构建

进入 Actions → Build and Push Docker Image → Run workflow，填写 `image_name` / `image_tags`，选择 `platforms`（默认双架构），按需填 `build_args`，勾选目标仓库即可（镜像名与 tag 均通过表单输入，`image-config.yaml` 已不再被 workflow 读取，可删除）。

也可通过 `dockerfile_url` 参数指定远程 Dockerfile 地址，或通过 `git_repo_url` 直接构建远程 Git 仓库中的 Dockerfile：

- **完整克隆**（保留全部提交历史与 tags，`--filter=blob:none` 减小传输）——部分项目（如 casdoor）构建时会用 go-git 读取 git 历史计算版本号，浅克隆会导致 `object not found` 构建失败。
- `git_repo_ref` 支持分支 / tag / commit，留空则使用仓库默认分支。
- `git_repo_path` 指定 Dockerfile 所在子目录，`build_context_path` 指定构建上下文根。

## Workflow 流程

```
prepare → build (按 platforms 并行) → merge (多架构 manifest)
                                         ↓
                              sync-aliyun (可选)
                              sync-huawei (可选)
                              sync-tencent-cnb (可选)
                              sync-dockerhub (可选)
                              sync-tcr (可选)
                              sync-quay (可选)
                                         ↓
                              cleanup-ghcr (未勾选 GHCR 时清理)
```

- **GHCR / TCR**：在 build 阶段直接推送，速度快
- **其他仓库**：构建完成后通过 skopeo 从 GHCR 同步，支持 `--all` 多架构复制
- **cleanup-ghcr**：未勾选 GHCR 时，构建结束后把本次推到 GHCR 的版本（用户 tag、`${sha}-amd64`/`${sha}-arm64` 临时 tag、本次运行中被顶替为 untagged 的旧版本）通过 API 逐个删除

## GHCR Retention Cleanup（GHCR 版本保留清理）

多架构构建会在 GHCR 留下 `${sha}-amd64` / `${sha}-arm64` 临时子 manifest，它们被 manifest list 按 digest 引用，**不能随手删**（删了会导致拉取报 `manifest unknown`），因此长期累积。`GHCR Retention Cleanup` workflow（每周一 04:17 UTC 定时，也可手动触发）负责安全地清理这些陈旧版本：

**保留规则**（满足任一即保留）：

1. 带有非临时 tag（即不是 `${sha}-<arch>` 形式）——现役 manifest list / 固定版本 tag
2. 创建时间在 `min_age_hours`（默认 24h）内——近期/进行中的构建
3. 只有临时 tag 或无 tag，且创建时间与某个带真实 tag 的版本相差 ±`correlation_hours`（默认 3h）内——现役 list 的子 manifest

其余（被顶替的旧 list、早已无引用的子 manifest、历史临时 tag）删除。

**使用**：

- 手动触发时 `dry_run` 默认开启，先跑一次预览 Summary 中的保留/删除计划，确认无误后再取消勾选执行真实删除
- 定时运行默认**只出报告不删除**；在仓库 Variables 里设置 `RETENTION_AUTO_DELETE=true` 后，定时运行才会真实删除
- `package_name` 留空 = 清理账号/组织下全部容器镜像包

> ⚠️ 清理会删除陈旧的 untagged 版本；如果有消费方按 digest 固定引用（`image@sha256:...`）旧版本，请不要开启自动删除，或调大 `min_age_hours`。

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

## Sync to CNB（仓库 / Release 制品同步到国内）

可复用工作流，把任意 GitHub 仓库的**全部分支 + 标签**和 **Release 制品**（名称、正文、预发布标记、附件）同步到 [cnb.cool](https://cnb.cool)。参考 TencentCloud/CubeSandbox 的做法做了通用化：原生 git push 做仓库镜像 + [`git-cnb`](https://cnb.cool/looc/git-cnb) CLI 传制品，无三方容器依赖。

### 1. 前置条件

| 项目 | 说明 |
|------|------|
| CNB 仓库 | 在 cnb.cool 建好目标仓库（slug 默认与 GitHub 同名，不同名用 `cnb_repo` 指定） |
| Secret | 源仓库配 `CNB_TOKEN`（cnb.cool → 设置 → 访问令牌，需推送/制品权限） |

### 2. 在源仓库添加调用工作流

`.github/workflows/sync-to-cnb.yml`：

```yaml
name: Sync to CNB
on:
  push:
    branches: [main]
    tags: ['*']
  release:
    types: [published]

jobs:
  sync:
    uses: abcdqwerxsa/MyActions/.github/workflows/sync-to-cnb.yml@main
    secrets:
      cnb_token: ${{ secrets.CNB_TOKEN }}
```

### 3. 可选 inputs

| Input | 默认 | 说明 |
|-------|------|------|
| `cnb_repo` | `github.repository` | CNB 目标 slug（CNB 用户名与 GitHub 不同时必填） |
| `sync_git` | `true` | 同步全部分支 + 标签（不推 `refs/pull/*`） |
| `sync_assets` | `true` | 同步 Release 元数据 + 附件（非 tag 事件自动跳过） |
| `release_tag` | 自动推断 | 手动指定要同步的 release 标签（补传旧版本时用） |

行为要点：仓库镜像与制品同步幂等可重跑；CNB 已存在的 release 保留原元数据不覆盖；同一 ref 的并发运行自动排队。

## Sync to GitCode（仓库 / Release 制品同步到 GitCode）

与 Sync to CNB 平级的可复用工作流，把任意 GitHub 仓库的**全部分支 + 标签**和 **Release 制品**（名称、正文、预发布标记、附件）同步到 [gitcode.com](https://gitcode.com)。

与 CNB 版的差异：GitCode 的 API 是 Gitee 风格 `/api/v5`（`access_token` 表单认证），**纯 curl 实现，无 CLI 依赖**。附件上传按文件名去重，重跑安全（幂等）。

### 1. 前置条件

| 项目 | 说明 |
|------|------|
| GitCode 仓库 | 在 gitcode.com 建好目标仓库（slug 默认与 GitHub 同名，不同名用 `gitcode_repo` 指定） |
| Secret | 源仓库配 `GITCODE_TOKEN`（gitcode.com → 个人设置 → 访问令牌，需推送/制品权限） |

### 2. 在源仓库添加调用工作流

`.github/workflows/sync-to-gitcode.yml`：

```yaml
name: Sync to GitCode
on:
  push:
    branches: [main]
    tags: ['*']
  release:
    types: [published]

jobs:
  sync:
    uses: abcdqwerxsa/MyActions/.github/workflows/sync-to-gitcode.yml@main
    secrets:
      gitcode_token: ${{ secrets.GITCODE_TOKEN }}
```

inputs 与 CNB 版一致（`gitcode_repo` / `sync_git` / `sync_assets` / `release_tag`），详见 `sync-to-gitcode.yml` 文件头注释。

> 附件单文件大小受平台限制（文件上传接口文档为 20M 量级），超大制品失败先查平台限制。
