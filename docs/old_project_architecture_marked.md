# 旧项目架构（标注版 — 红/黄/绿）

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
        Svc["🟢🟡🔵 Services"]
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

    classDef need fill:#51cf66,stroke:#2f9e44,color:#fff
    classDef maybe fill:#ffd43b,stroke:#f08c00,color:#000
    classDef nouse fill:#ff6b6b,stroke:#c92a2a,color:#fff

    class Svc,TD,RDS,Redis,EFS,Net need
    class ALB,TG,AutoScale,ECR,IAM maybe
    class R53,ACM,WAF,AzureAD,SM,EC2,SNS,EB,Lambda,GitHub nouse
```

## 图例

| 颜色 | 含义 | 数量 | 服务 |
|------|------|------|------|
| 🟢 绿色 | **保留** （需改造） | 6 | ECS Services, TaskDefs, RDS, Redis, EFS, Network |
| 🟡 黄色 | **可复用但需改造** | 5 | ALB, Target Groups, Autoscaling, ECR, IAM |
| 🔴 红色 | **过度设计 / Bayer 专属** | 11 | Route53, ACM, WAF, Azure AD, Secrets(OIDC), EC2, SNS+KMS+Alarms, EventBridge, Lambda, GitHub Actions |

## 红色服务删除原因

| 服务 | 原因 |
|------|------|
| Route53 + ACM | HTTP-only 部署不需要域名和证书 |
| WAFv2 | Langfuse API Key 已有鉴权 |
| Azure AD OIDC | Langfuse 自带认证 |
| Secrets Manager (OIDC) | 仅存 Azure AD 密钥，无需 |
| EC2 ASG | Fargate 替代 |
| SNS + KMS + Alarms | 过度精细，CloudWatch 直连 Slack 即可 |
| EventBridge ×2 + Lambda | LLM 观测平台需 24/7 运行，定时关停无意义 |
| GitHub Actions ×6 | `terraform apply` 本地执行足够 |
