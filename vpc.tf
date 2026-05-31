# =============================================================================
# VPC
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  count   = local.create_vpc ? 1 : 0

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.use_single_nat_gateway
  one_nat_gateway_per_az = !var.use_single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = local.base_tags
}

# =============================================================================
# VPC Endpoints (for ECS + Secrets Manager + ECR)
# =============================================================================
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "VPC Endpoints security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS from VPC"
  }

  tags = merge(local.base_tags, { Name = "${var.name}-vpc-endpoints" })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "${var.name}-ecr-api" })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "${var.name}-ecr-dkr" })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "${var.name}-secretsmanager" })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "${var.name}-logs" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.create_vpc ? module.vpc[0].private_route_table_ids : []
  tags              = merge(local.base_tags, { Name = "${var.name}-s3" })
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "${var.name}-sts" })
}
