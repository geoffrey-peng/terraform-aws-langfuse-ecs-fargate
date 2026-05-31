# =============================================================================
# EFS for ClickHouse Data Persistence
# =============================================================================

resource "aws_efs_file_system" "clickhouse" {
  creation_token  = "${var.name}-clickhouse"
  encrypted       = true
  throughput_mode = "elastic"

  tags = merge(local.base_tags, { Name = "${var.name}-clickhouse" })
}

resource "aws_efs_backup_policy" "clickhouse" {
  file_system_id = aws_efs_file_system.clickhouse.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_mount_target" "clickhouse" {
  count           = length(local.private_subnets)
  file_system_id  = aws_efs_file_system.clickhouse.id
  subnet_id       = local.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "clickhouse" {
  file_system_id = aws_efs_file_system.clickhouse.id

  root_directory {
    path = "/clickhouse"
    creation_info {
      owner_gid   = 101
      owner_uid   = 101
      permissions = "0755"
    }
  }

  posix_user {
    gid = 101
    uid = 101
  }

  tags = merge(local.base_tags, { Name = "${var.name}-clickhouse-ap" })
}
