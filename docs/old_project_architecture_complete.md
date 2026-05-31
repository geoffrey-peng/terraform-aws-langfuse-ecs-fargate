# 旧项目完整架构（Bayer Langfuse Platform — 所有服务）

```mermaid
graph LR
    subgraph U["外部"]
        USER["用户/客户端"]
        AZUREAD["Azure AD OIDC"]
        GITHUB["GitHub Actions"]
    end

    subgraph D["DNS & SSL"]
        R53["Route53 Hosted Zone"]
        R53_MAIN["A Record: main"]
        R53_SIDE["A Record: sidekick"]
        R53_NS["NS Delegation"]
        ACM["ACM root + wildcard"]
    end

    subgraph S["安全层"]
        WAF["WAFv2 Web ACL"]
        SM_SECRET["Azure OIDC Secret"]
    end

    subgraph L["ALB 层"]
        ALB_MOD["ph-ps-tf-module-alb"]
        ALB["ALB HTTPS :443"]
        LISTENER["HTTPS Listener"]
        TG_MAIN["Target Group: main"]
        TG_SIDE["Target Group: sidekick"]
        RULE_OIDC["OIDC Auth Rule"]
        RULE_SIDE["Static Forwarding Rule"]
    end

    subgraph E["ECS 层"]
        CLUSTER["ECS Cluster"]
        SVC_APP["Service: app"]
        SVC_WORKER["Service: worker"]
        SVC_OTHER["Service: other..."]
        TD_APP["TaskDef: app"]
        TD_WORKER["TaskDef: worker"]
        AutoScale["Autoscaling CPU/RAM"]
        CAP_PROV["EC2 Capacity Provider"]
    end

    subgraph C["EC2 层"]
        LT["Launch Template"]
        ASG["Auto Scaling Group"]
        AMI["AMI ECS-optimized"]
        KP["TLS Key Pair"]
        EBS["EBS gp3 30GB"]
        INST_PROF["EC2 Instance Profile"]
    end

    subgraph B["数据 & 存储"]
        ECR_REPO["ECR Repository"]
        RDS["RDS PostgreSQL db.t3.small"]
        RDS_SG["RDS SG"]
        RDS_SUBNET["DB Subnet Group"]
        RDS_PARAM["DB Parameter Group"]
        RDS_PASS["Random Password"]
        REDIS["Redis cache.t3.small 3.2"]
        REDIS_SG["Redis SG"]
        REDIS_SUBNET["Redis Subnet Group"]
    end

    subgraph F["EFS"]
        EFS_FS["EFS FileSystem"]
        EFS_AP["Access Point"]
        EFS_MT1["Mount Target A"]
        EFS_MT2["Mount Target B"]
        EFS_BCK["Backup Policy"]
    end

    subgraph N["网络"]
        VPC["VPC data source"]
        PRIV["Private Subnets"]
        PUB["Public Subnets"]
        ECS_SG["ECS SG"]
        ECS_EGR["ECS Egress"]
        EFS_SG["EFS NFS SG"]
    end

    subgraph I["IAM"]
        TASK_ROLE["Task Role"]
        EXEC_ROLE["Execution Role"]
        LAMBDA_ROLE["Lambda Role"]
        SCHED_ROLE["Scheduler Role"]
    end

    subgraph A["监控 & 告警"]
        LOG_ECS["CloudWatch ECS"]
        LOG_LAMBDA["CloudWatch Lambda"]
        ALARM_CPU["CPU Alarm"]
        ALARM_MEM["Memory Alarm"]
        ALARM_CNT["TaskCount Alarm"]
        KMS_KEY["KMS Key"]
        SNS_TOPIC["SNS Topic"]
        SNS_EMAIL["Email Subscription"]
    end

    subgraph T["定时关停"]
        EB_SHUT["EventBridge shutdown"]
        EB_START["EventBridge restart"]
        LAMBDA["Lambda Scaler"]
        LAMBDA_PERM["Lambda Permission"]
    end

    subgraph G["CI/CD"]
        BUILD["Build"]
        PLAN["Plan"]
        DEPLOY["Deploy"]
        DESTROY["Destroy"]
        CHECK_ECS["Check ECS"]
        ECR_FIND["ECR Findings"]
    end

    %% 外部 → DNS → ALB
    USER -->|"HTTPS"| R53
    R53 --> R53_MAIN --> ALB
    R53 --> R53_SIDE --> ALB
    ACM -.-> ALB
    WAF --> ALB
    AzureAD -.-> RULE_OIDC
    AZUREAD --> SM_SECRET

    %% ALB → ECS
    ALB --> TG_MAIN --> SVC_APP
    ALB --> TG_SIDE --> SVC_WORKER
    ALB --> TG_SIDE --> SVC_OTHER
    LISTENER --> RULE_OIDC
    LISTENER --> RULE_SIDE
    ALB_MOD -.-> ALB

    %% ECS 内部
    CLUSTER --> SVC_APP
    CLUSTER --> SVC_WORKER
    CLUSTER --> SVC_OTHER
    SVC_APP --> TD_APP
    SVC_WORKER --> TD_WORKER
    SVC_APP --> AutoScale
    SVC_WORKER --> AutoScale
    CAP_PROV --> ASG

    %% ECS → 数据
    TD_APP --> ECR_REPO
    TD_WORKER --> ECR_REPO
    TD_APP --> RDS
    TD_APP --> REDIS
    TD_WORKER --> RDS
    TD_WORKER --> REDIS
    TD_APP --> EFS_FS

    %% RDS
    RDS --> RDS_SG
    RDS --> RDS_SUBNET
    RDS --> RDS_PARAM
    RDS --> RDS_PASS

    %% EFS
    EFS_FS --> EFS_AP
    EFS_FS --> EFS_MT1 --> PRIV
    EFS_FS --> EFS_MT2 --> PRIV
    EFS_FS --> EFS_BCK

    %% EC2
    LT --> AMI
    LT --> KP
    LT --> EBS
    LT --> INST_PROF
    ASG --> LT
    SVC_APP -.-> ASG

    %% 网络
    ECS_SG --> SVC_APP
    ECS_SG --> SVC_WORKER
    EFS_SG --> EFS_MT1
    EFS_SG --> EFS_MT2
    VPC --> PRIV
    VPC --> PUB

    %% 监控
    ALARM_CPU --> SNS_TOPIC
    ALARM_MEM --> SNS_TOPIC
    ALARM_CNT --> SNS_TOPIC
    KMS_KEY --> SNS_TOPIC
    SNS_TOPIC --> SNS_EMAIL

    %% 定时
    EB_SHUT --> LAMBDA
    EB_START --> LAMBDA
    LAMBDA --> SVC_APP
    LAMBDA --> SVC_WORKER
    LAMBDA --> ASG

    %% IAM
    TASK_ROLE -.-> TD_APP
    EXEC_ROLE -.-> TD_APP
    LAMBDA_ROLE -.-> LAMBDA
    SCHED_ROLE -.-> EB_SHUT

    %% CI/CD
    GITHUB --> BUILD --> ECR_REPO
    GITHUB --> PLAN
    GITHUB --> DEPLOY
    GITHUB --> DESTROY
```

## 服务统计（55 个）

| 类别 | 数量 | 服务 |
|------|------|------|
| 外部/DNS/SSL | 8 | User, AzureAD, GitHub, Route53×4, ACM |
| 安全 | 2 | WAF, OIDC Secret |
| ALB | 7 | ALB Module, ALB, Listener, TG×2, Rules×2 |
| ECS | 8 | Cluster, Services×3, TaskDefs×2, Autoscale, CapacityProvider |
| EC2 | 6 | LT, ASG, AMI, KP, EBS, InstanceProfile |
| 数据/存储 | 9 | ECR, RDS×5, Redis×3 |
| EFS | 5 | FS, AP, MT×2, Backup |
| 网络 | 6 | VPC, Private/Public, ECS SG, Egress, EFS SG |
| IAM | 4 | TaskRole, ExecRole, LambdaRole, SchedulerRole |
| 监控 | 8 | Log×2, Alarm×3, KMS, SNS, Email |
| 定时 | 4 | EventBridge×2, Lambda×2 |
| CI/CD | 6 | Build, Plan, Deploy, Destroy, Check, ECR Findings |
| **合计** | **~55** | |
