# 镜像仓库配置说明

手动触发工作流时可选推送到以下镜像仓库。
在 GitHub 仓库 **Settings → Secrets and variables → Actions** 中配置：

## GitHub Container Registry (GHCR)
无需额外配置，自动使用 `GITHUB_TOKEN`。

## 阿里云 ACR
| 名称 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `ALIYUN_REGISTRY` | Variable | 仓库地址 | `registry.cn-hangzhou.aliyuncs.com` |
| `ALIYUN_NAMESPACE` | Variable | 命名空间 | `my-namespace` |
| `ALIYUN_REGISTRY_USERNAME` | Variable | 用户名 | `your-username` |
| `ALIYUN_REGISTRY_PASSWORD` | Secret | 密码 | `your-password` |

## 华为云 SWR
| 名称 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `HUAWEI_REGISTRY` | Variable | 仓库地址 | `swr.cn-north-4.myhuaweicloud.com` |
| `HUAWEI_NAMESPACE` | Variable | 组织名称 | `my-org` |
| `HUAWEI_REGISTRY_USERNAME` | Variable | 用户名 | `your-username` |
| `HUAWEI_REGISTRY_PASSWORD` | Secret | 密码/Token | `your-password` |

## 腾讯云 CNB
| 名称 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `TENCENT_REGISTRY` | Variable | 仓库地址 | `ccr.ccs.tencentyun.com` |
| `TENCENT_NAMESPACE` | Variable | 命名空间 | `my-namespace` |
| `TENCENT_REGISTRY_USERNAME` | Variable | 用户名 | `your-username` |
| `TENCENT_REGISTRY_PASSWORD` | Secret | 密码 | `your-password` |
