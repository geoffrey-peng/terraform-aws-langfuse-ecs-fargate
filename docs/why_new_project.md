# 为什么不基于旧项目改造，而是新建 ECS Fargate 项目

## 结论

旧项目 (~55 个服务) 只有约 **30%** 的部分对 Langfuse 有用。改造的成本远高于新建 — 删除无关服务 + 解耦 Bayer 依赖 + 重构为 Langfuse 架构 ≈ 重写一遍。

## 1. 架构层面的根本差异

| 维度 | 旧项目 | 新项目 | 差异 |
|------|--------|--------|------|
| **部署单元** | N 个 ECS Service（每个容器 1 个 Service + TaskDef）| 1 个 ECS Service（3 容器在 1 个 TaskDef 内）| 架构完全不同 |
| **容器关系** | 独立容器，通过网络通信 | **共置容器**（ClickHouse 用 localhost 访问）| 旧项目无法表达 "localhost 依赖" |
| **数据库** | 传统 RDS PostgreSQL (db.t3.small) | Aurora Serverless v2 (0.5-2 ACU) | Serverless 自动扩缩容 |
| **Redis** | 3.2.10 / cache.t3.small | 7.1 / cache.t4g.small (TLS) | 版本 + 类型都不同 |
| **认证** | Azure AD OIDC (Bayer Tenant 硬编码) | Langfuse 内置 email+password | 完全不同的鉴权体系 |
| **ALB** | HTTPS + 外部 ALB Module + Route53 + ACM | HTTP-only + 原生 aws_lb | 从 4 个服务简化为 1 个 resource |

## 2. Bayer 专属硬编码（无法复用）

不改代码就无法部署在其他 AWS 账号：

```hcl
# 硬编码 1: Azure AD Tenant ID
# ph-ps-tf-modules/alb.tf:111
issuer = "https://login.microsoftonline.com/fcb2b37b-5da0-466b-9b83-0014b67a7c78/v2.0"

# 硬编码 2: RDS 子网 + 安全组 (deployment/hosting.tf:52-54)
subnet_ids = (var.environment == "prod" ? ["subnet-0d25f100d7e208161", "subnet-0dd9bb495684ac00e"] : ...)
vpc_security_group_ids = (var.environment == "prod" ? ["sg-0186fbbc4e382ee70"] : ...)

# 硬编码 3: ACM 证书 ARN (ph-ps-tf-modules/alb.tf:215-218)
certificate_arn = (
  var.environment == "prod" ? "arn:aws:acm:us-east-1:969331008209:certificate/3077479f-..." :
  var.environment == "qa"   ? "arn:aws:acm:eu-central-1:241533148771:certificate/12c62dca-..." :
  "arn:aws:acm:eu-central-1:135808953630:certificate/1576974c-..."
)

# 硬编码 4: VPC 查询仅靠 tag:environment 标签
# deployment/networking.tf:3-6
data "aws_vpc" "vpc" {
  filter { name = "tag:environment"; values = [var.environment] }
}

# 硬编码 5: 12 个 Bayer 全球 NAT Gateway IP
# ph-ps-tf-modules/variables.tf:112-128
alb_additional_allowed_cidrs = ["3.126.214.238/32", "52.57.178.236/32", ...]

# 硬编码 6: Redis SG ID
# deployment/hosting.tf:82
security_group_ids = ["sg-0ad45a2a26454af95"]
```

**结论**: 每个硬编码都要找替代方案，改造 ≈ 拆了重建。

## 3. 外部依赖链

旧项目依赖 Bayer 内部的私有模块和仓库：

```
ph-ps-tf-modules
  ├── github.com/bayer-int/ph-ps-tf-module-alb (私有)
  ├── Bayer VPC (tag:environment 标签约定)
  ├── Bayer Route53 Hosted Zone (ds.bayer.int.com)
  ├── Bayer ACM Certificate ARNs
  ├── Bayer Azure AD Tenant
  └── GitHub Actions Runners (AssumeRole: cloudops)
```

拿掉这些外部依赖后，项目几乎不剩什么 — 核心逻辑（ECS + RDS + Redis + EFS + ALB）用 Terraform 原生 resource 重写反而更干净。

## 4. 为什么官方架构更好

旧项目中，每个容器是一个独立的 ECS Service 和 Task Definition。但 Langfuse 的 **web 和 worker 需要共享同一个 ClickHouse 实例**，且 ClickHouse 是嵌入式部署（sidecar pattern），三个容器必须在同一台机器上通过 localhost 通信。

| 旧项目模式 | 新项目模式 |
|-----------|-----------|
| 1 ECS Service per Container | 1 ECS Service with 3 Containers |
| 容器间通过网络通信 | 容器间通过 localhost |
| 独立扩缩容 | 同生共死，一起伸缩 |
| ClickHouse 地址是外部 IP/DNS | ClickHouse URL = `http://localhost:8123` |

这是**架构层面的根本差异**。旧项目的 `for_each` 模式（按容器遍历创建独立 Service）无法满足 Langfuse 对容器共置的要求。

## 5. 代码量对比

| 项目 | 文件数 | 代码行数 | 外部依赖 |
|------|--------|----------|---------|
| 旧项目 | ~45 files | ~2500 lines | 5+ Bayer 私有模块 |
| 新项目 (ECS Fargate) | 17 files | ~850 lines | 0 外部依赖 |

## 6. 总结

| 原因 | 影响 |
|------|------|
| 架构不同（独立容器 vs 共置容器）| 需要重写整个 ECS 部分 |
| Bayer 硬编码（6 处以上）| 逐个替换比新建更费时 |
| 外部依赖链 | 无法独立部署，删除后只剩 30% 有用 |
| 过度设计（~55 个服务）| 实际 Langfuse 只需 ~15 个 resource |
| 官方架构更匹配 | aws ecs fargate 模式原生支持 sidecar 容器 |
| 中国区/海外兼容 | 旧项目依赖 Route53+ACM → 中国区无法直接使用 |

**改为基于官方 aws_ecs_fargate 模块从头构建 ECS 方案，代码量减少 66%，零外部依赖，可直接在任何 AWS 账号部署。**
