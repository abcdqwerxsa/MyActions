# 镜像仓库 Secrets 配置说明

手动触发工作流时可选推送到以下镜像仓库，需在 GitHub 仓库 Settings → Secrets 中预先配置：

## GitHub Container Registry (GHCR)
无需额外配置，自动使用 `GITHUB_TOKEN`。

## 阿里云 ACR
| Secret 名称 | 说明 | 示例 |
|---|---|---|
| `ALIYUN_REGISTRY` | 仓库地址 | `registry.cn-hangzhou.aliyuncs.com` |
| `ALIYUN_NAMESPACE` | 命名空间 | `my-namespace` |
| `ALIYUN_REGISTRY_USERNAME` | 用户名 | `your-username` |
| `ALIYUN_REGISTRY_PASSWORD` | 密码 | `your-password` |

## 华为云 SWR
| Secret 名称 | 说明 | 示例 |
|---|---|---|
| `HUAWEI_REGISTRY` | 仓库地址 | `swr.cn-north-4.myhuaweicloud.com` |
| `HUAWEI_NAMESPACE` | 组织名称 | `my-org` |
| `HUAWEI_REGISTRY_USERNAME` | 用户名 | `your-username` |
| `HUAWEI_REGISTRY_PASSWORD` | 密码/Token | `your-password` |

## 腾讯云 CNB
| Secret 名称 | 说明 | 示例 |
|---|---|---|
| `TENCENT_REGISTRY` | 仓库地址 | `ccr.ccs.tencentyun.com` |
| `TENCENT_NAMESPACE` | 命名空间 | `my-namespace` |
| `TENCENT_REGISTRY_USERNAME` | 用户名 | `your-username` |
| `TENCENT_REGISTRY_PASSWORD` | 密码 | `your-password` |
