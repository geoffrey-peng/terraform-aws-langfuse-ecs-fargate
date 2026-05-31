# =============================================================================
# Security Groups
# =============================================================================

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB security group"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_inbound_cidrs
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "HTTP from ${ingress.value}"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "${var.name}-alb" })
}

# ECS Service Security Group
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs"
  description = "ECS tasks security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Langfuse web from ALB"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Internal communication between containers in the same task"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.base_tags, { Name = "${var.name}-ecs" })
}

# PostgreSQL Security Group
resource "aws_security_group" "postgres" {
  name        = "${var.name}-postgres"
  description = "PostgreSQL security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
    description     = "PostgreSQL from ECS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "${var.name}-postgres" })
}

# Redis Security Group
resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "Redis security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
    description     = "Redis from ECS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "${var.name}-redis" })
}

# EFS Security Group
resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "EFS security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
    description     = "NFS from ECS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "${var.name}-efs" })
}
