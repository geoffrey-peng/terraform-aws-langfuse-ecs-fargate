# Langfuse on ECS Fargate (Terraform)

基于 AWS ECS Fargate 部署 [Langfuse](https://langfuse.com/) v3 的生产就绪 Terraform 模块。

## 架构

| 组件 | 规格 | 说明 |
|------|------|------|
| **ECS Fargate** | 1 Task × 3 Containers | ClickHouse + langfuse-web + langfuse-worker 共享同一实例 |
| **Aurora PostgreSQL Serverless v2** | 0.5–2 ACU | 元数据存储，自动扩缩容 |
| **ElastiCache Redis 7.1** | cache.t4g.small | 缓存 + 队列，TLS 传输加密 |
| **EFS** | 弹性吞吐量 | ClickHouse 数据持久化 |
| **ALB** | HTTP (端口 80) | 互联网/内网访问 |
| **S3** | 版本化 + 生命周期策略 | Langfuse 对象存储 + ALB 日志 |
| **Secrets Manager** | AWS 托管 KMS | 统一管理所有密码和密钥 |

**估算成本**: ~$250/月 (海外区域，1实例基线)

## 前置条件

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) 已配置凭证 (`aws configure`)
- 目标 AWS 账号有足够的配额（VPC、ECS、RDS、ElastiCache、EFS）

## 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/geoffrey-peng/terraform-aws-langfuse-ecs-fargate.git langfuse-ecs
cd langfuse-ecs

# 2. 按需修改配置（所有可配项均已在 terraform.tfvars 中列出并注释）
vim terraform.tfvars

# 3. 初始化 & 部署
terraform init
terraform plan
terraform apply

# 4. 获取访问地址
terraform output alb_url
# 输出: http://<alb-dns>.elb.amazonaws.com
```

首次部署完成后，浏览器打开 ALB URL，点击 "Sign up" 创建管理员账号即可使用。

部署完成后，从 **AWS Secrets Manager** (`langfuse-configuration`) 获取 API 密钥用于测试：

```bash
aws secretsmanager get-secret-value \
  --secret-id langfuse-configuration \
  --query SecretString \
  --output text | jq .
```

## 配置说明

所有可配置项均在 `terraform.tfvars` 中，按重要性分 8 块，注释掉即为默认值。下面逐块说明关键选项。

### 1. 区域 & 命名

```hcl
region = "us-east-1"
name   = "langfuse"       # 资源前缀，影响桶名、集群名等
```

### 2. VPC 网络（二选一）

**方式 A — 自动创建（默认）**：`vpc_id = null`，模块会自动创建 VPC（10.0.0.0/16）、公私子网、NAT 网关、Internet 网关、6 个 VPC Endpoints。

**方式 B — 使用已有 VPC**：取消注释并填入自己的资源 ID：

```hcl
vpc_id             = "vpc-xxxxxxxx"
private_subnet_ids = ["subnet-xxx", "subnet-yyy"]
public_subnet_ids  = ["subnet-xxx", "subnet-yyy"]
```

> 已有 VPC 要求：私有子网有 NAT 出口；公有子网有 Internet 网关。如无 VPC Endpoints，模块会自动创建 6 个。

### 3. ALB 访问控制

```hcl
alb_scheme            = "internet-facing"   # 或 "internal"
ingress_inbound_cidrs = ["0.0.0.0/0"]      # 生产环境建议限定 IP
```

### 4. 容器资源规格

三个容器共享 1 个 Fargate Task，Task CPU/Memory = 三者之和。**修改时确保总和是 Fargate 有效组合**（参考 [官方文档](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)）：

| 容器 | CPU 默认 | Memory 默认 | 说明 |
|------|----------|-------------|------|
| ClickHouse | 1024 | 2048 | 存事件/观测数据 |
| langfuse-web | 512 | 4096 | Node.js，内存大户 |
| langfuse-worker | 512 | 1024 | 异步处理 |
| **合计** | **2048** | **7168** | |

> 如果调大 `langfuse_web_memory`，需同步改 `ecs.tf` 中 `NODE_OPTIONS=--max-old-space-size=xxx`（设为内存的 ~75%）。

### 5. 数据库 & 缓存

```hcl
# Aurora PostgreSQL Serverless v2
postgres_instance_count = 1       # 生产建议 >= 2
postgres_min_capacity   = 0.5     # ACU
postgres_max_capacity   = 2.0

# ElastiCache Redis
cache_node_type      = "cache.t4g.small"
cache_instance_count = 1          # 生产建议 >= 2
redis_multi_az       = false
```

### 6. 镜像

海外区默认直接拉取 Docker Hub，中国区需推送到 ECR 后填地址（见下方「中国区部署」）。

### 7-8. 功能开关 & 高级选项

遥测、实验特性、队列参数、额外环境变量等，详见 `terraform.tfvars` 注释。

## S3 桶配置

### 默认行为：自动创建

模块自动创建名为 `{name}-{aws_account_id}` 的 S3 桶，启用版本控制和生命周期策略（90 天→IA，180 天→Glacier IR）。

```hcl
# 无需额外配置，桶名称在 s3.tf 中定义：
# bucket = "${var.name}-${data.aws_caller_identity.current.account_id}"
```

### 使用已存在的 S3 桶

如果你已有 S3 桶，修改 `s3.tf` 中的桶名或替换为 data source：

**选项 A — 直接改名**（最简单）：

编辑 `s3.tf` 第 6 行：

```hcl
resource "aws_s3_bucket" "langfuse" {
  bucket = "my-existing-bucket-name"   # 改为你的桶名
  # ...
}
```

然后注释掉 `aws_s3_bucket_versioning`、`aws_s3_bucket_public_access_block`、`aws_s3_bucket_lifecycle_configuration` 等已有配置的 resource，避免冲突。

**选项 B — 用 data source 引用已有桶，传给 ECS 环境变量**：

1. 在 `s3.tf` 或 `main.tf` 中添加：

```hcl
data "aws_s3_bucket" "existing" {
  bucket = "my-existing-bucket-name"
}
```

2. 修改 `ecs.tf` 中 `local.common_env` 的 `LANGFUSE_S3_BUCKET` 值为 `data.aws_s3_bucket.existing.id`。
3. 注释掉原有的 `aws_s3_bucket.langfuse` 及相关 resource。

> **注意**：已有桶仍需 ALB 日志写入权限（`s3:PutObject`），模块中的 `aws_s3_bucket_policy` 需要指向你的桶。

## 完整变量参考

> `terraform.tfvars` 已包含所有变量的注释版，以下为补充说明的速查表。

### 通用

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `name` | string | `"langfuse"` | 资源名称前缀 |
| `region` | string | `"us-east-1"` | AWS 区域 |
| `tags` | map(string) | `{}` | 附加标签 |

### 网络

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `vpc_cidr` | string | `"10.0.0.0/16"` | VPC CIDR（新建 VPC 时生效）|
| `vpc_id` | string | `null` | 已有 VPC ID，null 则自动创建 |
| `private_subnet_ids` | list(string) | `null` | 已有私有子网 ID 列表 |
| `public_subnet_ids` | list(string) | `null` | 已有公有子网 ID 列表 |
| `use_single_nat_gateway` | bool | `true` | 单 NAT 网关（省钱）vs 每 AZ 一个 |

### PostgreSQL (Aurora Serverless v2)

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `postgres_instance_count` | number | `1` | 实例数量 |
| `postgres_min_capacity` | number | `0.5` | 最小 ACU |
| `postgres_max_capacity` | number | `2.0` | 最大 ACU |
| `postgres_version` | string | `"15.12"` | PostgreSQL 版本 |

### Redis (ElastiCache)

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `cache_node_type` | string | `"cache.t4g.small"` | 节点类型 |
| `cache_instance_count` | number | `1` | 节点数量 |
| `redis_multi_az` | bool | `false` | 多 AZ 高可用 |

### 容器资源

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `clickhouse_cpu` | number | `1024` | ClickHouse CPU (1024=1vCPU) |
| `clickhouse_memory` | number | `2048` | ClickHouse 内存 (MiB) |
| `langfuse_web_cpu` | number | `512` | Web 容器 CPU |
| `langfuse_web_memory` | number | `4096` | Web 容器内存 (MiB) |
| `langfuse_worker_cpu` | number | `512` | Worker 容器 CPU |
| `langfuse_worker_memory` | number | `1024` | Worker 容器内存 (MiB) |

> **资源总和**: Task CPU = 2048, Task Memory = 7168 MiB（3 容器合计）。Fargate 要求 CPU/memory 为有效组合，修改时请参考 [Fargate 任务大小限制](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)。

### 镜像

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `langfuse_image` | string | `"langfuse/langfuse:3"` | Web 镜像 |
| `langfuse_worker_image` | string | `"langfuse/langfuse-worker:3"` | Worker 镜像 |
| `clickhouse_image` | string | `"clickhouse/clickhouse-server:24.3-alpine"` | ClickHouse 镜像 |

### ALB

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `alb_scheme` | string | `"internet-facing"` | `internet-facing` 或 `internal` |
| `ingress_inbound_cidrs` | list(string) | `["0.0.0.0/0"]` | 入站 CIDR 白名单 |

## 中国区部署

中国区 (cn-north-1 / cn-northwest-1) 需额外配置：

```hcl
# terraform.tfvars
region = "cn-north-1"

# Docker Hub 在中国区不可用，需先将镜像推送到 ECR
langfuse_image        = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse:3"
langfuse_worker_image = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse-worker:3"
clickhouse_image      = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/clickhouse/clickhouse-server:24.3-alpine"

# Route53 域名 + ACM 证书可自行添加，替换 ALB HTTP-only 方案
```

推送镜像到 ECR 的步骤：

```bash
# 拉取镜像
docker pull langfuse/langfuse:3
docker pull langfuse/langfuse-worker:3
docker pull clickhouse/clickhouse-server:24.3-alpine

# 打标签 & 推送（以 langfuse 为例，其他同理）
aws ecr create-repository --repository-name langfuse/langfuse --region cn-north-1
aws ecr get-login-password --region cn-north-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.cn-north-1.amazonaws.com.cn
docker tag langfuse/langfuse:3 <account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse:3
docker push <account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse:3
```

## 测试

部署完成后，使用测试脚本验证功能：

### 安装依赖

```bash
pip install langfuse
```

### 运行测试

```bash
# 设置环境变量
export LANGFUSE_SECRET_KEY="sk-lf-..."     # 从 Secrets Manager 获取
export LANGFUSE_PUBLIC_KEY="pk-lf-..."     # 从 Secrets Manager 获取
export LANGFUSE_HOST="http://<alb-dns>.elb.amazonaws.com"

# Trace 测试 (span + generation + score)
python tests/test_trace.py

# Prompt 管理测试 (create + fetch + compile + trace)
python tests/test_prompt.py

# curl 原生命令测试
bash tests/test_trace.sh
```

> API 密钥存储在 AWS Secrets Manager → `langfuse-configuration` → `LANGFUSE_SALT`、`LANGFUSE_NEXTAUTH_SECRET`。登录 Langfuse Web UI 后在 Settings → API Keys 创建项目密钥。

## 密码管理

所有密码和密钥存储在 **AWS Secrets Manager** (`langfuse-configuration`)，使用 AWS 托管 KMS 加密：

```json
{
  "DATABASE_URL": "postgresql://user:pass@host:5432/langfuse",
  "SALT": "...",
  "NEXTAUTH_SECRET": "...",
  "CLICKHOUSE_PASSWORD": "...",
  "REDIS_AUTH": "..."
}
```

查询命令：

```bash
aws secretsmanager get-secret-value \
  --secret-id langfuse-configuration \
  --query SecretString \
  --output text | jq .
```

> Secrets Manager 使用 AWS 默认 KMS key (`aws/secretsmanager`)，**不产生额外 KMS 费用**。

## 文件结构

```
.
├── main.tf              # Provider + data sources
├── versions.tf          # Provider 版本约束
├── variables.tf         # 所有输入变量
├── locals.tf            # 本地值 (VPC 决策、URL 拼接)
├── terraform.tfvars     # 部署配置 (修改此项，不改 variables.tf)
├── vpc.tf               # VPC 模块 + 6 个 VPC Endpoints
├── ecs.tf               # ECS 集群、任务定义、服务 (核心)
├── postgresql.tf        # Aurora PostgreSQL Serverless v2
├── redis.tf             # ElastiCache Redis
├── efs.tf               # EFS 文件系统 + Access Point
├── s3.tf                # S3 桶 + 版本化 + 生命周期 + ALB 日志策略
├── alb.tf               # ALB + Target Group + Listener
├── secrets.tf           # Secrets Manager + 随机密码生成
├── iam.tf               # ECS 执行角色 + 任务角色
├── security_groups.tf   # 5 个安全组 (ALB/ECS/PG/Redis/EFS)
├── cloudwatch.tf        # CloudWatch 日志组
├── outputs.tf           # 输出值
├── tests/
│   ├── test_trace.py        # 🧪 Trace 测试脚本
│   ├── test_prompt.py       # 🧪 Prompt 管理测试脚本
│   └── test_trace.sh        # 🧪 curl 测试脚本
```

## 常见问题

### ECS 任务起不来？

```bash
# 查看停止原因
aws ecs describe-tasks --cluster langfuse --tasks <task-id>

# 查看容器日志
aws logs tail /ecs/langfuse --follow
```

### Web 容器 OOM (JavaScript heap out of memory)

默认 Web 容器内存 4096 MiB，Node.js `--max-old-space-size=3072`。如果 OOM，增大 `langfuse_web_memory` 并同步调整 `NODE_OPTIONS`（在 `ecs.tf` 的 web 容器定义中）。

### 已有 VPC 下 S3 Endpoint 路由表不匹配

`vpc.tf` 第 94 行已处理：当使用已有 VPC 时，S3 Gateway Endpoint 的 `route_table_ids` 设为空数组 `[]`，由 VPC 的默认路由表自动处理。

### 无法访问 Langfuse Web

1. 确认 ALB security group 允许你的 IP (`ingress_inbound_cidrs`)
2. 确认 ECS 任务状态为 `RUNNING`
3. 确认所有 3 个容器（clickhouse、web、worker）健康检查通过

## 安全说明

- 生产环境建议将 `ingress_inbound_cidrs` 改为限定 IP 范围
- 建议启用 `redis_at_rest_encryption = true`（成本略增）
- 生产数据库建议 `postgres_instance_count >= 2` + `redis_multi_az = true`
- 若需 HTTPS，可添加 Route53 域名 + ACM 证书 + 修改 ALB Listener 为 443
