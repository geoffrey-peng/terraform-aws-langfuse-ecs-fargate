# 新项目架构（Langfuse ECS Fargate）

```mermaid
graph TB
    subgraph "用户访问"
        USER[用户/浏览器]
        SDK[Python/JS SDK<br/>langfuse client]
    end

    subgraph "ALB HTTP"
        ALB[Application Load Balancer<br/>internet-facing<br/>HTTP:80]
        TG_WEB[Target Group<br/>port 3000<br/>health: /api/public/health]
        ALB_SG[ALB Security Group<br/>ingress: 80 from CIDRs]
    end

    subgraph "ECS Fargate: 1 Task × 3 Containers"
        subgraph "Container: clickhouse"
            CH[ClickHouse 24.3<br/>port 8123 HTTP<br/>port 9000 Native<br/>health: wget /ping]
        end
        subgraph "Container: langfuse-web"
            WEB[Langfuse Web v3<br/>Next.js port 3000<br/>NODE_OPTIONS=--max-old-space-size=3072<br/>health: node http.get /api/public/health]
        end
        subgraph "Container: langfuse-worker"
            WORKER[Langfuse Worker v3<br/>port 3030<br/>async ingestion processor]
        end
        CH ---|"localhost:8123<br/>localhost:9000"| WEB
        CH ---|"localhost:8123"| WORKER
        WEB ---|"localhost:3000"| WORKER
    end

    subgraph "ECS Service"
        ECS_CLUSTER[ECS Cluster<br/>containerInsights enabled]
        ECS_SERVICE[ECS Service: langfuse<br/>FARGATE / 1 task<br/>circuit-breaker enabled]
        ECS_TD[Task Definition: langfuse<br/>CPU=2048 Mem=7168<br/>awsvpc network mode]
    end

    subgraph "数据层"
        subgraph "Aurora PostgreSQL Serverless v2"
            RDS_CLUSTER[Aurora Cluster<br/>15.12 / Serverless v2<br/>0.5-2 ACU]
            RDS_INSTANCE[DB Instance<br/>db.serverless]
            RDS_SG[RDS Security Group<br/>ingress: 5432 from ECS SG]
        end
        subgraph "ElastiCache Redis 7.1"
            REDIS_CLUSTER[Redis Replication Group<br/>cache.t4g.small / 1 node<br/>TLS transit encryption<br/>maxmemory-policy=noeviction]
            REDIS_SG[Redis Security Group<br/>ingress: 6379 from ECS SG]
        end
    end

    subgraph "存储层"
        EFS[EFS File System<br/>elastic throughput<br/>encrypted<br/>backup enabled]
        EFS_AP[EFS Access Point<br/>path: /clickhouse<br/>uid:gid=101:101]
        EFS_MT_A[EFS Mount Target<br/>private subnet A]
        EFS_MT_B[EFS Mount Target<br/>private subnet B]
        EFS_SG[EFS Security Group<br/>ingress: 2049 from ECS SG]
    end

    subgraph "对象存储"
        S3[S3 Bucket<br/>{name}-{account_id}<br/>versioned + lifecycle<br/>ALB access logs enabled]
        S3_POLICY_S3_BUCKET_POLICY[ALB Logs Bucket Policy<br/>s3:PutObject for ELB]
        S3_LIFECYCLE[Lifecycle: 90d→IA / 180d→Glacier IR]
    end

    subgraph "安全"
        SECRETS[Secrets Manager<br/>langfuse-configuration<br/>AWS-managed KMS]
        SECRETS_ITEMS["DATABASE_URL<br/>SALT<br/>NEXTAUTH_SECRET<br/>CLICKHOUSE_PASSWORD<br/>REDIS_AUTH<br/>ENCRYPTION_KEY"]
        RANDOM[Random Passwords<br/>postgres / clickhouse / redis<br/>Random Bytes: salt / nextauth / encryption]
    end

    subgraph "VPC"
        VPC_MOD[VPC Module<br/>terraform-aws-modules/vpc/aws<br/>auto-create or existing]
        PRIVATE_SUBNETS[Private Subnets<br/>ECS + RDS + Redis + EFS]
        PUBLIC_SUBNETS[Public Subnets<br/>ALB only]
        NAT[NAT Gateway<br/>single / per-AZ]
        IGW[Internet Gateway]
    end

    subgraph "VPC Endpoints ×6"
        VPCE_ECR_API[ECR API]
        VPCE_ECR_DKR[ECR DKR]
        VPCE_SM[Secrets Manager]
        VPCE_LOGS[CloudWatch Logs]
        VPCE_S3[S3 Gateway]
        VPCE_STS[STS]
        VPCE_SG[VPC Endpoints SG<br/>ingress: 443 from VPC]
    end

    subgraph "IAM"
        EXEC_ROLE[ECS Execution Role<br/>ECR pull + SecretsManager read]
        TASK_ROLE[ECS Task Role<br/>S3 read/write]
    end

    subgraph "监控"
        CW_LOG[CloudWatch Log Group<br/>/ecs/langfuse / 30 days]
    end

    %% === 连接关系 ===
    USER -->|"HTTP :80"| ALB
    SDK -->|"HTTP :80"| ALB
    ALB --> TG_WEB
    TG_WEB --> ECS_SERVICE
    ALB_SG --> ALB

    ECS_SERVICE --> ECS_TD
    ECS_TD --> CH
    ECS_TD --> WEB
    ECS_TD --> WORKER

    CH -->|"mount /var/lib/clickhouse"| EFS_AP
    EFS_AP --> EFS
    EFS --> EFS_MT_A
    EFS --> EFS_MT_B
    EFS_MT_A --> PRIVATE_SUBNETS
    EFS_MT_B --> PRIVATE_SUBNETS

    WEB -->|"DATABASE_URL"| RDS_CLUSTER
    WORKER -->|"DATABASE_URL"| RDS_CLUSTER
    RDS_CLUSTER --> RDS_INSTANCE

    WEB -->|"REDIS_HOST:6379"| REDIS_CLUSTER
    WORKER -->|"REDIS_HOST:6379"| REDIS_CLUSTER

    WEB -->|"LANGFUSE_S3_*"| S3
    WORKER -->|"LANGFUSE_S3_*"| S3
    ALB -->|"access logs"| S3

    SECRETS --> SECRETS_ITEMS
    RANDOM --> SECRETS
    EXEC_ROLE --> SECRETS
    TASK_ROLE --> S3

    ECS_SERVICE --> PRIVATE_SUBNETS
    ALB --> PUBLIC_SUBNETS

    PRIVATE_SUBNETS --> NAT
    PUBLIC_SUBNETS --> IGW
    NAT --> IGW

    PRIVATE_SUBNETS --> VPCE_ECR_API
    PRIVATE_SUBNETS --> VPCE_ECR_DKR
    PRIVATE_SUBNETS --> VPCE_SM
    PRIVATE_SUBNETS --> VPCE_LOGS
    PRIVATE_SUBNETS --> VPCE_S3
    PRIVATE_SUBNETS --> VPCE_STS

    ECS_SERVICE --> EXEC_ROLE
    ECS_SERVICE --> TASK_ROLE

    ECS_SERVICE --> CW_LOG
    CH --> CW_LOG
    WEB --> CW_LOG
    WORKER --> CW_LOG

    RDS_SG --> RDS_CLUSTER
    REDIS_SG --> REDIS_CLUSTER
    EFS_SG --> EFS_MT_A
    EFS_SG --> EFS_MT_B

    classDef compute fill:#4dabf7,stroke:#1971c2,color:#fff
    classDef database fill:#ffd43b,stroke:#f08c00,color:#000
    classDef storage fill:#69db7c,stroke:#2f9e44,color:#fff
    classDef network fill:#da77f2,stroke:#9c36b5,color:#fff
    classDef security fill:#ff6b6b,stroke:#c92a2a,color:#fff

    class CH,WEB,WORKER,ECS_CLUSTER,ECS_SERVICE,ECS_TD compute
    class RDS_CLUSTER,RDS_INSTANCE,REDIS_CLUSTER database
    class EFS,S3,EFS_AP,S3_LIFECYCLE storage
    class VPC_MOD,PRIVATE_SUBNETS,PUBLIC_SUBNETS,NAT,IGW,ALB,ALB_SG,VPCE_ECR_API,VPCE_ECR_DKR,VPCE_SM,VPCE_LOGS,VPCE_S3,VPCE_STS network
    class SECRETS,RANDOM,SECRETS_ITEMS,EXEC_ROLE,TASK_ROLE,RDS_SG,REDIS_SG,EFS_SG,VPCE_SG security
```

## 服务统计

| 类别 | 服务 | 数量 |
|------|------|------|
| 计算 | ECS Cluster, ECS Service, Task Definition, ClickHouse 容器, Web 容器, Worker 容器 | 6 |
| 网络 | VPC, NAT, IGW, ALB, ALB SG, 公有/私有子网, 6×VPC Endpoints | 13 |
| 数据库 | Aurora Cluster, Aurora Instance, Redis Cluster, RDS SG, Redis SG | 5 |
| 存储 | EFS, EFS AP, EFS Mount×2, EFS SG, S3, S3 Policy, S3 Lifecycle | 8 |
| 安全 | Secrets Manager, Random Passwords×3, Random Bytes×3, ECS SG, IAM×2, VPCE SG | 11 |
| 监控 | CloudWatch Log Group | 1 |
| **合计** | | **45** |

## 与旧项目对比

| 维度 | 旧项目 | 新项目 |
|------|--------|--------|
| 总服务数 | ~55 | 45 (Terraform resources) |
| 代码文件 | ~45 | 17 |
| 外部依赖 | 5+ | 0 |
| 容器架构 | 独立 Service per Container | 3 in 1 Task (sidecar) |
| 数据库 | 传统 RDS | Aurora Serverless v2 |
| 部署方式 | GitHub Actions (6 workflows) | `terraform apply` |
| 认证 | Azure AD OIDC | Langfuse 内置 |
| 域名/证书 | Route53 + ACM | HTTP-only |
| 中国区兼容 | 不支持 | 仅需改镜像地址 |
