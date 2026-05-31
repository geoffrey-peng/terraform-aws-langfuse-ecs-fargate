# =============================================================================
# S3 Bucket for Langfuse
# =============================================================================

resource "aws_s3_bucket" "langfuse" {
  bucket        = "${var.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(local.base_tags, {
    Name    = "${var.name}-s3"
    Service = "langfuse"
  })
}

resource "aws_s3_bucket_versioning" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_elb_service_account" "current" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.langfuse.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.current.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.langfuse.arn}/alb-logs/*"
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id

  rule {
    id     = "langfuse-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }
  }
}
