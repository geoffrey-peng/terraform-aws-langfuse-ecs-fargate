# =============================================================================
# General
# =============================================================================
variable "name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "langfuse"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# VPC
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_id" {
  description = "Existing VPC ID (skip VPC creation if set)"
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs (required if vpc_id is set)"
  type        = list(string)
  default     = null
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs (required if vpc_id is set)"
  type        = list(string)
  default     = null
}

variable "use_single_nat_gateway" {
  description = "Use a single NAT Gateway (cheaper) instead of one per AZ"
  type        = bool
  default     = true
}

# =============================================================================
# PostgreSQL (Aurora Serverless v2)
# =============================================================================
variable "postgres_instance_count" {
  description = "Number of Aurora PostgreSQL instances"
  type        = number
  default     = 1
}

variable "postgres_min_capacity" {
  description = "Min ACU for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "postgres_max_capacity" {
  description = "Max ACU for Aurora Serverless v2"
  type        = number
  default     = 2.0
}

variable "postgres_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.12"
}

# =============================================================================
# Redis (ElastiCache)
# =============================================================================
variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "cache_instance_count" {
  description = "Number of Redis nodes"
  type        = number
  default     = 1
}

variable "redis_at_rest_encryption" {
  description = "Enable at-rest encryption for Redis"
  type        = bool
  default     = false
}

variable "redis_multi_az" {
  description = "Enable Multi-AZ for Redis"
  type        = bool
  default     = false
}

# =============================================================================
# ClickHouse
# =============================================================================
variable "clickhouse_cpu" {
  description = "CPU units for ClickHouse container (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "clickhouse_memory" {
  description = "Memory for ClickHouse container (MiB)"
  type        = number
  default     = 2048
}

variable "clickhouse_efs_storage_gb" {
  description = "EFS storage size note (EFS is elastic, this is just informational)"
  type        = number
  default     = 20
}

# =============================================================================
# Langfuse Web
# =============================================================================
variable "langfuse_web_cpu" {
  description = "CPU units for Langfuse web container (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "langfuse_web_memory" {
  description = "Memory for Langfuse web container (MiB)"
  type        = number
  default     = 4096
}

variable "langfuse_web_replicas" {
  description = "Number of Langfuse web task replicas"
  type        = number
  default     = 1
}

# =============================================================================
# Langfuse Worker
# =============================================================================
variable "langfuse_worker_cpu" {
  description = "CPU units for Langfuse worker container (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "langfuse_worker_memory" {
  description = "Memory for Langfuse worker container (MiB)"
  type        = number
  default     = 1024
}

variable "langfuse_worker_replicas" {
  description = "Number of Langfuse worker task replicas"
  type        = number
  default     = 1
}

# =============================================================================
# Langfuse Images
# =============================================================================
variable "langfuse_image" {
  description = "Langfuse web Docker image"
  type        = string
  default     = "langfuse/langfuse:3"
}

variable "langfuse_worker_image" {
  description = "Langfuse worker Docker image"
  type        = string
  default     = "langfuse/langfuse-worker:3"
}

variable "clickhouse_image" {
  description = "ClickHouse Docker image"
  type        = string
  default     = "clickhouse/clickhouse-server:24.3-alpine"
}

# =============================================================================
# ALB
# =============================================================================
variable "alb_scheme" {
  description = "ALB scheme: internet-facing or internal"
  type        = string
  default     = "internet-facing"
}

variable "ingress_inbound_cidrs" {
  description = "CIDRs allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# =============================================================================
# Langfuse Configuration
# =============================================================================
variable "use_encryption_key" {
  description = "Whether to use an encryption key for credential store"
  type        = bool
  default     = true
}

variable "telemetry_enabled" {
  description = "Enable Langfuse telemetry"
  type        = bool
  default     = false
}

variable "enable_experimental_features" {
  description = "Enable Langfuse experimental features"
  type        = bool
  default     = false
}

variable "ingestion_queue_delay_ms" {
  description = "Ingestion queue delay in milliseconds"
  type        = number
  default     = null
}

variable "ingestion_clickhouse_write_interval_ms" {
  description = "ClickHouse write interval in milliseconds"
  type        = number
  default     = null
}

variable "additional_env" {
  description = "Additional environment variables for Langfuse containers"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
