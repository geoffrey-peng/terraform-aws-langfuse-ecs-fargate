locals {
  # VPC decision
  create_vpc = var.vpc_id == null

  # Subnets
  private_subnets = local.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnets  = local.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
  vpc_id          = local.create_vpc ? module.vpc[0].vpc_id : var.vpc_id

  # Tags
  base_tags = merge(
    {
      Name    = var.name
      Service = "langfuse"
    },
    var.tags
  )

  # Langfuse configs that need special formatting
  database_url = "postgresql://${aws_rds_cluster.postgres.master_username}:${random_password.postgres_password.result}@${aws_rds_cluster.postgres.endpoint}:5432/langfuse"

  redis_host = aws_elasticache_replication_group.redis.primary_endpoint_address

  # URL for NEXTAUTH (set after ALB is created)
  nextauth_url = "http://${aws_lb.this.dns_name}"
}
