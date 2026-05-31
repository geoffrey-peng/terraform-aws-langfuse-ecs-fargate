# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.base_tags
}

# =============================================================================
# ECS Task Definition (3 containers in 1 task)
#
# Fargate task sizing:
#   Task CPU must be >= sum of container CPU reservations
#   Task memory must be >= sum of container memory reservations
#   Valid Fargate combos at 2048 CPU: 4096-16384 MiB
# =============================================================================

locals {
  task_cpu    = var.clickhouse_cpu + var.langfuse_web_cpu + var.langfuse_worker_cpu
  task_memory = var.clickhouse_memory + var.langfuse_web_memory + var.langfuse_worker_memory

  # Common environment variables (non-sensitive)
  common_env = concat(
    [
      { name = "CLICKHOUSE_URL", value = "http://localhost:8123" },
      { name = "CLICKHOUSE_USER", value = "clickhouse" },
      { name = "CLICKHOUSE_CLUSTER_ENABLED", value = "false" },
      { name = "REDIS_HOST", value = local.redis_host },
      { name = "REDIS_PORT", value = "6379" },
      { name = "REDIS_TLS_ENABLED", value = "true" },
      { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET", value = aws_s3_bucket.langfuse.id },
      { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION", value = data.aws_region.current.region },
      { name = "LANGFUSE_S3_EVENT_UPLOAD_PREFIX", value = "events/" },
      { name = "LANGFUSE_S3_MEDIA_UPLOAD_BUCKET", value = aws_s3_bucket.langfuse.id },
      { name = "LANGFUSE_S3_MEDIA_UPLOAD_REGION", value = data.aws_region.current.region },
      { name = "LANGFUSE_S3_MEDIA_UPLOAD_PREFIX", value = "media/" },
      { name = "LANGFUSE_S3_BATCH_EXPORT_ENABLED", value = "true" },
      { name = "LANGFUSE_S3_BATCH_EXPORT_BUCKET", value = aws_s3_bucket.langfuse.id },
      { name = "LANGFUSE_S3_BATCH_EXPORT_REGION", value = data.aws_region.current.region },
      { name = "LANGFUSE_S3_BATCH_EXPORT_PREFIX", value = "exports/" },
      { name = "TELEMETRY_ENABLED", value = tostring(var.telemetry_enabled) },
      { name = "LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES", value = tostring(var.enable_experimental_features) },
    ],
    var.ingestion_queue_delay_ms != null ? [{ name = "LANGFUSE_INGESTION_QUEUE_DELAY_MS", value = tostring(var.ingestion_queue_delay_ms) }] : [],
    var.ingestion_clickhouse_write_interval_ms != null ? [{ name = "LANGFUSE_INGESTION_CLICKHOUSE_WRITE_INTERVAL_MS", value = tostring(var.ingestion_clickhouse_write_interval_ms) }] : [],
    [for env in var.additional_env : { name = env.name, value = env.value }]
  )

  # Sensitive variables injected from Secrets Manager
  common_secrets = [
    { name = "DATABASE_URL", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:DATABASE_URL::" },
    { name = "SALT", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:SALT::" },
    { name = "CLICKHOUSE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:CLICKHOUSE_PASSWORD::" },
    { name = "REDIS_AUTH", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:REDIS_AUTH::" },
  ]

  web_secrets = concat(local.common_secrets, [
    { name = "NEXTAUTH_SECRET", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:NEXTAUTH_SECRET::" },
    { name = "ENCRYPTION_KEY", valueFrom = "${aws_secretsmanager_secret.langfuse.arn}:ENCRYPTION_KEY::" },
  ])
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.task_cpu
  memory                   = local.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode(concat(
    [
      # ---- ClickHouse Container ----
      {
        name      = "clickhouse"
        image     = var.clickhouse_image
        essential = true
        cpu       = var.clickhouse_cpu
        memory    = var.clickhouse_memory

        portMappings = [
          { containerPort = 8123, hostPort = 8123, protocol = "tcp" },
          { containerPort = 9000, hostPort = 9000, protocol = "tcp" },
        ]

        environment = [
          { name = "CLICKHOUSE_DB", value = "langfuse" },
          { name = "CLICKHOUSE_USER", value = "clickhouse" },
          { name = "CLICKHOUSE_PASSWORD", value = random_password.clickhouse_password.result },
        ]

        mountPoints = [
          {
            sourceVolume  = "clickhouse-data"
            containerPath = "/var/lib/clickhouse"
          }
        ]

        healthCheck = {
          command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8123/ping || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 5
          startPeriod = 60
        }

        ulimits = [
          { name = "nofile", softLimit = 262144, hardLimit = 262144 }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.ecs.name
            awslogs-region        = data.aws_region.current.region
            awslogs-stream-prefix = "clickhouse"
          }
        }
      },

      # ---- Langfuse Web Container ----
      {
        name      = "langfuse-web"
        image     = var.langfuse_image
        essential = true
        cpu       = var.langfuse_web_cpu
        memory    = var.langfuse_web_memory

        portMappings = [
          { containerPort = 3000, hostPort = 3000, protocol = "tcp" },
        ]

        environment = concat(local.common_env, [
          { name = "NODE_OPTIONS", value = "--max-old-space-size=3072" },
          { name = "NEXTAUTH_URL", value = local.nextauth_url },
          { name = "CLICKHOUSE_MIGRATION_URL", value = "clickhouse://clickhouse:${random_password.clickhouse_password.result}@localhost:9000/langfuse" },
        ])

        secrets = local.web_secrets

        healthCheck = {
          command     = ["CMD-SHELL", "node -e \"require('http').get('http://localhost:3000/api/public/health',(r)=>{process.exit(r.statusCode===200?0:1)})\""]
          interval    = 30
          timeout     = 5
          retries     = 5
          startPeriod = 90
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.ecs.name
            awslogs-region        = data.aws_region.current.region
            awslogs-stream-prefix = "langfuse-web"
          }
        }
      },

      # ---- Langfuse Worker Container ----
      {
        name      = "langfuse-worker"
        image     = var.langfuse_worker_image
        essential = true
        cpu       = var.langfuse_worker_cpu
        memory    = var.langfuse_worker_memory

        portMappings = [
          { containerPort = 3030, hostPort = 3030, protocol = "tcp" },
        ]

        environment = local.common_env
        secrets     = local.common_secrets

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.ecs.name
            awslogs-region        = data.aws_region.current.region
            awslogs-stream-prefix = "langfuse-worker"
          }
        }
      },
    ],
  ))

  volume {
    name = "clickhouse-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.clickhouse.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.clickhouse.id
        iam             = "DISABLED"
      }
    }
  }

  tags = local.base_tags
}

# =============================================================================
# ECS Service
# =============================================================================

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.private_subnets
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "langfuse-web"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.base_tags
}
