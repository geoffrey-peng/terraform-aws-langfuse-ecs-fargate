# =============================================================================
# Application Load Balancer (HTTP only, no HTTPS/Route53/ACM)
# =============================================================================

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.alb_scheme == "internal"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnets

  access_logs {
    bucket  = aws_s3_bucket.langfuse.id
    prefix  = "alb-logs"
    enabled = true
  }

  tags = merge(local.base_tags, { Name = var.name })
}

resource "aws_lb_target_group" "web" {
  name        = "${var.name}-web"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/api/public/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.base_tags, { Name = "${var.name}-web-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = merge(local.base_tags, { Name = "${var.name}-listener" })
}
