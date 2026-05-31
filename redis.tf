# =============================================================================
# ElastiCache Redis
# =============================================================================

resource "random_password" "redis_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "aws_elasticache_parameter_group" "redis" {
  family = "redis7"
  name   = "${var.name}-redis-params"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis"
  subnet_ids = local.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = var.name
  description                = "Redis for Langfuse"
  node_type                  = var.cache_node_type
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  automatic_failover_enabled = var.cache_instance_count > 1
  num_cache_clusters         = var.cache_instance_count
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  engine                     = "redis"
  engine_version             = "7.1"
  auth_token                 = random_password.redis_password.result
  transit_encryption_enabled = true
  at_rest_encryption_enabled = var.redis_at_rest_encryption
  multi_az_enabled           = var.redis_multi_az

  tags = local.base_tags
}
