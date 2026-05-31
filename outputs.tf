# =============================================================================
# Outputs
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_url" {
  description = "Langfuse access URL"
  value       = "http://${aws_lb.this.dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "s3_bucket_name" {
  description = "S3 bucket name for Langfuse"
  value       = aws_s3_bucket.langfuse.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.langfuse.arn
}

output "rds_endpoint" {
  description = "Aurora PostgreSQL endpoint"
  value       = aws_rds_cluster.postgres.endpoint
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = local.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = local.public_subnets
}
