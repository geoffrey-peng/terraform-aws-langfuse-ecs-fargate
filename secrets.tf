# =============================================================================
# Random Secrets Generation
# =============================================================================

resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "random_bytes" "salt" {
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  length = 32
}

resource "random_bytes" "encryption_key" {
  count  = var.use_encryption_key ? 1 : 0
  length = 32
}

# =============================================================================
# AWS Secrets Manager - central configuration store
# =============================================================================

resource "aws_secretsmanager_secret" "langfuse" {
  name = "${var.name}-configuration"

  tags = local.base_tags
}

resource "aws_secretsmanager_secret_version" "langfuse" {
  secret_id = aws_secretsmanager_secret.langfuse.id
  secret_string = jsonencode({
    DATABASE_URL        = local.database_url
    NEXTAUTH_SECRET     = random_bytes.nextauth_secret.base64
    SALT                = random_bytes.salt.base64
    ENCRYPTION_KEY      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
    CLICKHOUSE_PASSWORD = random_password.clickhouse_password.result
    REDIS_AUTH          = random_password.redis_password.result
  })
}
