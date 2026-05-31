# =============================================================================
# Langfuse ECS Fargate — 部署配置模板
# 复制此文件为 terraform.tfvars，取消注释需要修改的项即可
# =============================================================================

# =============================================================================
# 1. 区域 & 命名
# =============================================================================
region = "us-east-1"                       
# region = "cn-north-1"     # 北京
# name   = "langfuse"                        # 资源前缀，默认 "langfuse"

# =============================================================================
# 2. VPC 网络（二选一）
# =============================================================================
# --- 方式 A：自动创建 VPC（默认）---
vpc_id = null
# vpc_cidr              = "10.0.0.0/16"      # 新建 VPC 的 CIDR
# use_single_nat_gateway = true               # true=单NAT便宜, false=每AZ一个高可用

# --- 方式 B：使用已有 VPC（取消下面注释，同时注释掉上面的 vpc_id=null）---
# vpc_id             = "vpc-xxxxxxxx"
# private_subnet_ids = ["subnet-xxx", "subnet-yyy"]
# public_subnet_ids  = ["subnet-xxx", "subnet-yyy"]

# =============================================================================
# 3. ALB 访问控制
# =============================================================================
# alb_scheme            = "internet-facing"   # internet-facing 或 internal
# ingress_inbound_cidrs = ["0.0.0.0/0"]      # 生产环境建议改为限定 IP 范围

# =============================================================================
# 4. 容器资源规格（3 个容器共享 1 个 Fargate Task）
# =============================================================================
# Task 总 CPU = clickhouse_cpu + web_cpu + worker_cpu = 2048
# Task 总 Mem = clickhouse_memory + web_memory + worker_memory = 7168 MiB
# 修改时确保总和是 Fargate 有效组合: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size

# --- ClickHouse ---
# clickhouse_cpu    = 1024                    # 默认 1024 (1 vCPU)
# clickhouse_memory = 2048                    # 默认 2048 MiB

# --- Langfuse Web (吃内存大户，Node.js 堆) ---
# langfuse_web_cpu    = 512                   # 默认 512
# langfuse_web_memory = 4096                  # 默认 4096 MiB（低于 4096 可能 OOM）

# --- Langfuse Worker ---
# langfuse_worker_cpu    = 512                # 默认 512
# langfuse_worker_memory = 1024               # 默认 1024 MiB

# =============================================================================
# 5. 数据库 & 缓存
# =============================================================================
# --- Aurora PostgreSQL Serverless v2 ---
# postgres_instance_count = 1                 # 实例数，生产建议 >= 2
# postgres_min_capacity   = 0.5               # 最小 ACU（最低 0.5）
# postgres_max_capacity   = 2.0               # 最大 ACU
# postgres_version        = "15.12"           # PostgreSQL 版本

# --- ElastiCache Redis ---
# cache_node_type      = "cache.t4g.small"    # 节点类型
# cache_instance_count = 1                    # 节点数，生产建议 >= 2
# redis_multi_az       = false                # 多 AZ 高可用
# redis_at_rest_encryption = false            # 静态加密

# =============================================================================
# 6. 容器镜像
# =============================================================================
# 海外区（默认）直接拉取 Docker Hub：
# langfuse_image        = "langfuse/langfuse:3"
# langfuse_worker_image = "langfuse/langfuse-worker:3"
# clickhouse_image      = "clickhouse/clickhouse-server:24.3-alpine"

# 中国区需推送到 ECR 后取消注释：
# langfuse_image        = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse:3"
# langfuse_worker_image = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/langfuse/langfuse-worker:3"
# clickhouse_image      = "<account>.dkr.ecr.cn-north-1.amazonaws.com.cn/clickhouse/clickhouse-server:24.3-alpine"

# =============================================================================
# 7. Langfuse 功能开关
# =============================================================================
# telemetry_enabled            = false        # 遥测上报
# enable_experimental_features = false        # 实验特性
# use_encryption_key           = true         # 凭证加密

# =============================================================================
# 8. 高级选项
# =============================================================================
# ingestion_queue_delay_ms               = null   # 数据写入队列延迟 (ms)
# ingestion_clickhouse_write_interval_ms = null   # ClickHouse 写入间隔 (ms)

# 额外环境变量（注入到 web + worker 容器）:
# additional_env = [
#   { name = "CUSTOM_VAR", value = "custom_value" },
# ]

# 额外标签:
# tags = {
#   Environment = "production"
#   Team        = "ai"
# }
