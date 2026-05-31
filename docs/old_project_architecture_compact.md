# 旧项目架构（压缩版，可在 mermaid.live 渲染）

```mermaid
graph LR
    subgraph U["用户 & CI"]
        User["👤 用户"]
        GitHub["🔧 GitHub Actions"]
    end

    subgraph D["DNS & 安全"]
        R53["🌐 Route53"]
        ACM["🔒 ACM"]
        WAF["🛡️ WAFv2"]
        AzureAD["🔐 Azure AD OIDC"]
        SM["🔑 Secrets Manager"]
    end

    subgraph L["ALB 层"]
        ALB["⚖️ ALB HTTPS :443"]
        TG["📌 Target Groups"]
    end

    subgraph E["ECS 层"]
        Svc["🟢🟡🔵 Services app/worker"]
        TD["📦 TaskDefinitions"]
        AutoScale["📈 Autoscaling"]
        EC2["🖥️ EC2 ASG"]
    end

    subgraph B["数据 & 存储"]
        RDS["🐘 RDS PostgreSQL"]
        Redis["🔴 ElastiCache Redis"]
        ECR["📦 ECR"]
        EFS["📁 EFS"]
    end

    subgraph M["监控 & 定时"]
        SNS["📢 SNS+KMS+Alarms"]
        EB["⏰ EventBridge cron"]
        Lambda["⚡ Lambda Scaler"]
    end

    subgraph X["IAM & 网络"]
        IAM["🎫 Task+Exec+Lambda Roles"]
        Net["🏗️ VPC+Subnets+SG"]
    end

    User -->|"HTTPS"| R53 --> ALB
    ACM -.-> ALB
    WAF --> ALB
    AzureAD -.-> ALB
    SM -.-> AzureAD
    ALB --> TG --> Svc
    Svc --> TD --> ECR
    TD --> RDS
    TD --> Redis
    TD --> EFS
    Svc --> AutoScale
    Svc -.-> EC2
    SNS --> Svc
    EB --> Lambda --> Svc
    IAM -.-> TD
    Svc --> Net
    GitHub --> ECR
    GitHub --> Svc
```

## 旧项目全量服务清单（55 个）

| 类别 | 服务 | 是否必要 |
|------|------|----------|
| DNS | Route53 Hosted Zone, A Records×2, NS Delegation, ACM×3 | ❌ Bayer 域名绑定 |
| 安全 | WAFv2, Azure AD OIDC, Secrets Manager (OIDC) | ❌ Langfuse 自带鉴权 |
| ALB | ALB (外部模块), Target Groups×N, HTTPS Listener, Listener Rules | ⚠️ 部分可复用 |
| ECS | Cluster, Services×N, TaskDefs×N, Autoscaling | ✅ 核心（需改架构） |
| EC2 | LaunchTemplate, ASG, AMI, KeyPair | ❌ Fargate 替代 |
| ECR | ECR Repository | ⚠️ 可选 |
| EFS | FileSystem, AccessPoint, MountTarget×2, BackupPolicy | ✅ 需要 |
| RDS | Instance, SubnetGroup, ParameterGroup, Password, SnapshotID | ✅ 改为 Aurora |
| Redis | Cluster, SubnetGroup | ✅ 需要 |
| SG | ECS SG, EFS SG, ECS Egress, RDS SG, Redis SG | ✅ 精简 |
| IAM | TaskRole, ExecutionRole, LambdaRole, SchedulerRole | ✅ 精简 |
| SNS/KMS | SNS Topic, KMS Key, Email Subscription | ❌ 过度设计 |
| CloudWatch | Log Groups×2, Alarms×3 | ⚠️ 精简 |
| EventBridge | Shutdown/Start Schedulers, Lambda Scaler, Lambda Permission | ❌ 定时关停无意义 |
| GitHub | 6 Workflows (Build/Plan/Deploy/Destroy/Check/Findings) | ❌ 本地 apply 足够 |

> ✅ = 保留（需改造）| ⚠️ = 可保留但非必需 | ❌ = 过度设计/Bayer专属
