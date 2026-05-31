# 新项目架构（Langfuse ECS Fargate）

```mermaid
graph LR
    subgraph U["用户访问"]
        User["👤 用户/浏览器"]
        SDK["📡 Python/JS SDK"]
    end

    subgraph L["ALB 层"]
        ALB["⚖️ ALB HTTP :80"]
        TG["📌 Target Group :3000"]
        ALB_SG["🔒 ALB SG"]
    end

    subgraph E["ECS Fargate — 1 Task × 3 Containers"]
        CH["📊 ClickHouse 24.3<br/>:8123 / :9000"]
        WEB["🌐 langfuse-web v3<br/>:3000"]
        WORKER["⚙️ langfuse-worker v3<br/>:3030"]
    end

    subgraph C["ECS 资源"]
        Cluster["🎯 ECS Cluster"]
        Svc["🟢 ECS Service"]
        TD["📦 Task Definition<br/>CPU=2048 Mem=7168"]
    end

    subgraph D["数据层"]
        RDS["🐘 Aurora PostgreSQL<br/>Serverless v2 0.5-2 ACU"]
        RDS_SG["🔒 RDS SG"]
        Redis["🔴 ElastiCache Redis 7.1<br/>cache.t4g.small"]
        Redis_SG["🔒 Redis SG"]
    end

    subgraph S["存储"]
        EFS["📁 EFS<br/>encrypted + backup"]
        EFS_AP["📌 Access Point<br/>/clickhouse uid:gid=101:101"]
        EFS_SG["🔒 EFS SG"]
        S3["🪣 S3 Bucket<br/>versioned + lifecycle"]
        S3_POLICY["📋 S3 Bucket Policy<br/>ALB logs"]
    end

    subgraph K["安全"]
        Secrets["🔑 Secrets Manager<br/>langfuse-configuration<br/>AWS-managed KMS"]
        Random["🎲 Random Passwords<br/>postgres/clickhouse/redis<br/>salt/nextauth/encryption"]
    end

    subgraph I["IAM"]
        ExecRole["🎫 Execution Role<br/>ECR pull + Secrets read"]
        TaskRole["🎫 Task Role<br/>S3 read/write"]
    end

    subgraph N["网络"]
        VPC["🏗️ VPC<br/>auto-create or existing"]
        PrivSub["🔒 Private Subnets"]
        PubSub["🌐 Public Subnets"]
        NAT["🚪 NAT Gateway"]
        IGW["🌍 Internet Gateway"]
        VPCE["🔗 6×VPC Endpoints<br/>ECR/SM/Logs/S3/STS"]
    end

    subgraph M["监控"]
        CW["📋 CloudWatch Logs<br/>30 days retention"]
    end

    %% 用户 → ALB
    User -->|"HTTP :80"| ALB
    SDK -->|"HTTP :80"| ALB
    ALB --> TG --> Svc

    %% ECS 内部
    Svc --> TD
    TD --> CH
    TD --> WEB
    TD --> WORKER
    Cluster --> Svc

    %% localhost 通信
    WEB -.->|"localhost:8123"| CH
    WEB -.->|"localhost:3030"| WORKER
    WORKER -.->|"localhost:8123"| CH

    %% 数据连接
    WEB -->|"DATABASE_URL"| RDS
    WEB -->|"REDIS_HOST"| Redis
    WORKER -->|"DATABASE_URL"| RDS
    WORKER -->|"REDIS_HOST"| Redis

    %% 存储
    WEB -->|"S3_MEDIA_UPLOAD"| S3
    WORKER -->|"S3_EVENT_UPLOAD"| S3
    CH -->|"/var/lib/clickhouse"| EFS
    EFS --> EFS_AP
    ALB -.->|"access logs"| S3

    %% 安全
    Secrets -.->|"注入密钥"| WEB
    Secrets -.->|"注入密钥"| WORKER
    Secrets -.->|"注入密码"| CH
    Random --> Secrets

    %% IAM
    ExecRole -.-> WEB
    ExecRole -.-> WORKER
    TaskRole -.-> S3

    %% 网络
    Svc --> PrivSub
    ALB --> PubSub
    PrivSub --> NAT --> IGW
    PubSub --> IGW
    PrivSub --> VPCE
    VPC --> PrivSub
    VPC --> PubSub

    %% SG
    ALB_SG -.-> ALB
    RDS_SG -.-> RDS
    Redis_SG -.-> Redis
    EFS_SG -.-> EFS

    %% 日志
    Svc --> CW
    CH --> CW
    WEB --> CW
    WORKER --> CW
```

## 服务统计（45 个 Terraform Resource）

| 类别 | 数量 | 服务 |
|------|------|------|
| 计算 | 4 | ECS Cluster, Service, TaskDef, 3容器(1个定义) |
| 网络 | 12 | VPC, Private/Public Subnets, NAT, IGW, ALB, TG, ALB SG, 6×VPCE |
| 数据库 | 4 | Aurora Cluster, Aurora Instance, RDS SG, Redis Cluster, Redis SG |
| 存储 | 7 | EFS, EFS AP, EFS MT×2, EFS SG, S3, S3 Policy, S3 Lifecycle |
| 安全 | 6 | Secrets Manager, Random×3(pw), Random×3(bytes), ECS SG, VPCE SG |
| IAM | 2 | Execution Role, Task Role |
| 监控 | 1 | CloudWatch Log Group |
| **合计** | **~45** | |

## 与旧项目对比

| 维度 | 旧项目 | 新项目 |
|------|--------|--------|
| 总 Resource 数 | ~55 | ~45 |
| 代码文件 | ~45 | 17 |
| 外部依赖 | 5+ | 0 |
| 容器架构 | 独立 Service per Container | 3 in 1 Task |
| 数据库 | 传统 RDS | Aurora Serverless v2 |
| 部署 | GitHub Actions ×6 | `terraform apply` |
| 认证 | Azure AD OIDC | Langfuse 内置 |
| 中国区兼容 | 不支持 | 改镜像地址即可 |
