# =============================================================================
# CloudWatch Log Group for ECS container logs
# =============================================================================

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30

  tags = merge(local.base_tags, { Name = "${var.name}-logs" })
}
