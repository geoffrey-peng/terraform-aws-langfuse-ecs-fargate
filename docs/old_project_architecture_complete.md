# 旧项目完整架构（Bayer Langfuse Platform — 所有服务）

```mermaid
graph TB
    subgraph "外部"
        USER[用户/客户端]
        AZUREAD[Azure AD / Entra ID<br/>OIDC Provider]
        GITHUB[GitHub Actions<br/>CI/CD]
    end

    subgraph "Route53"
        R53[Route53 Public Hosted Zone<br/>e.g. aaihub.int.bayer.com]
        R53_RECORD_MAIN["A Record: langfuse.{domain}"]
        R53_RECORD_SIDEKICK["A Record: {container}.langfuse.{domain}"]
        R53_NS[NS Delegation Records<br/>多账号 DNS 委托]
    end

    subgraph "ACM"
        ACM_ROOT[ACM Certificate<br/>root domain]
        ACM_WILDCARD[ACM Certificate<br/>*.subdomain]
        ACM_VALIDATION[Certificate Validation<br/>DNS records]
    end

    subgraph "ALB Module 外部模块"
        ALB_MOD["ph-ps-tf-module-alb<br/>GitHub v3.0.4"]
        WAF[WAFv2 Web ACL]
    end

    subgraph "ALB 层"
        ALB[Application Load Balancer<br/>HTTPS:443 — internet-facing]
        TG_MAIN[Target Group: main container]
        TG_SIDEKICK["Target Group: sidekick containers"]
        LISTENER[HTTPS Listener :443]
        OIDC_RULE[Listener Rule: Authenticate-OIDC<br/>Azure AD auth for main container]
        SIDEKICK_RULE[Listener Rule: Static Forwarding<br/>host-header routing for sidekick]
    end

    subgraph "ECS Cluster"
        ECS_CLUSTER[ECS Cluster<br/>containerInsights enabled]
        ECS_SERVICE_APP[ECS Service: app]
        ECS_SERVICE_WORKER[ECS Service: worker]
        ECS_SERVICE_OTHER["ECS Service: other containers..."]
        ECS_TD_APP[Task Definition: app<br/>FARGATE / EC2]
        ECS_TD_WORKER[Task Definition: worker<br/>FARGATE / EC2]
        ECS_AUTOSCALE[App Autoscaling<br/>Target Tracking CPU/RAM]
        CAPACITY_PROVIDER[EC2 Capacity Provider<br/>ASG managed scaling]
    end

    subgraph "EC2 层 仅 EC2 启动模式"
        LAUNCH_TEMPLATE[Launch Template<br/>Amazon Linux 2 ECS-optimized]
        ASG[Auto Scaling Group<br/>spread across AZs]
        AMI[AMI Data Source<br/>ECS-optimized AMI]
        KEYPAIR[TLS Private Key + EC2 Key Pair<br/>RSA 4096]
        EBS[EBS gp3 加密<br/>30GB default]
        INSTANCE_PROFILE[EC2 Instance Profile<br/>ECS task role]
    end

    subgraph "ECR"
        ECR_REPO[ECR Repository<br/>per container image]
    end

    subgraph "EFS"
        EFS_FS[EFS File System<br/>encrypted + lifecycle IA]
        EFS_AP[EFS Access Point<br/>posix_user + /ecs path]
        EFS_MT_1[EFS Mount Target<br/>private subnet 0]
        EFS_MT_2[EFS Mount Target<br/>private subnet 1]
        EFS_BACKUP[EFS Backup Policy<br/>ENABLED]
    end

    subgraph "RDS 传统 PostgreSQL"
        RDS_MOD[RDS Module<br/>deployment/modules/rds]
        RDS_INSTANCE[aws_db_instance<br/>db.t3.small / gp2 20GB]
        RDS_SG[RDS Security Group<br/>per environment]
        RDS_SUBNET[DB Subnet Group<br/>per environment]
        RDS_PARAM[DB Parameter Group<br/>postgres 16]
        RDS_PASSWORD[Random Password<br/>16 chars]
        RDS_SNAPSHOT_ID[Random ID for Snapshots]
    end

    subgraph "ElastiCache"
        REDIS[Redis Cluster<br/>cache.t3.small / 3.2.10<br/>1 node / TLS enabled]
        REDIS_SG[Redis Security Group<br/>sg-0ad45a2a26454af95]
        REDIS_SUBNET[Redis Subnet Group<br/>per environment]
    end

    subgraph "VPC 已有 VPC Data Source"
        VPC["data.aws_vpc<br/>filter by tag:environment"]
        PRIVATE_SUBNETS["data.aws_subnets<br/>tag:Name=*Private*"]
        PUBLIC_SUBNETS["data.aws_subnets<br/>tag:Name=*Public*"]
    end

    subgraph "Security Groups"
        ECS_SG[ECS Service SG<br/>ingress from ALB SG]
        ECS_SG_EGRESS[ECS Egress Rules<br/>customizable]
        EFS_SG[EFS NFS SG<br/>port 2049 + 2999]
    end

    subgraph "IAM"
        TASK_ROLE[ECS Task Role<br/>custom policy: RDS/S3/Glue/Athena<br/>Timestream/Secrets/KMS/CloudWatch/EFS/STS]
        EXEC_ROLE[ECS Execution Role<br/>SecretsManager + KMS Decrypt]
        LAMBDA_ROLE[Lambda Scheduler Role<br/>ECS UpdateService + ENI]
        SCHEDULER_ROLE[EventBridge Scheduler Role<br/>Invoke Lambda]
    end

    subgraph "Secrets Manager"
        SECRET[Azure AD OIDC Secret<br/>client_id + client_secret]
    end

    subgraph "SNS + KMS"
        KMS_KEY[KMS Key<br/>for SNS encryption<br/>auto-rotation]
        SNS_TOPIC[SNS Topic: ecs-alerts<br/>KMS encrypted]
        SNS_EMAIL[SNS Email Subscription<br/>per recipient]
    end

    subgraph "CloudWatch"
        LOG_ECS[Log Group: /aws/ecs/{prefix}-cluster<br/>30 days]
        LOG_LAMBDA[Log Group: /aws/lambda/{prefix}-lambda-scheduler<br/>30 days]
        ALARM_CPU[CPU Utilization Alarm]
        ALARM_RAM[Memory Utilization Alarm]
        ALARM_COUNT[Desired Task Count Alarm]
    end

    subgraph "EventBridge + Lambda 定时关停"
        SCHEDULER_SHUT[EventBridge Scheduler: shutdown<br/>cron expression]
        SCHEDULER_START[EventBridge Scheduler: restart<br/>cron expression]
        LAMBDA_SCALER[Lambda: scaler function<br/>python3.12 / 256MB<br/>sets ECS desired=0 / restore]
        LAMBDA_PERM[Lambda Permission<br/>allow scheduler.amazonaws.com]
    end

    subgraph "CI/CD GitHub Actions"
        BUILD[Build Workflow<br/>Docker build + push to ECR]
        PLAN[Plan on PR<br/>terraform plan]
        DEPLOY[Deploy Workflow<br/>terraform apply]
        DESTROY[Destroy Workflow<br/>terraform destroy]
        CHECK_ECS[Check ECS Deployment Status]
        ECR_FINDINGS[Summarize ECR Findings]
    end

    %% === 连接关系 ===
    USER -->|"HTTPS :443<br/>langfuse.{domain}"| R53
    R53 --> R53_RECORD_MAIN
    R53_RECORD_MAIN --> ALB
    R53_RECORD_SIDEKICK --> ALB
    ALB --> TG_MAIN
    ALB --> TG_SIDEKICK
    TG_MAIN --> ECS_SERVICE_APP
    TG_SIDEKICK --> ECS_SERVICE_WORKER
    TG_SIDEKICK --> ECS_SERVICE_OTHER
    LISTENER --> OIDC_RULE
    LISTENER --> SIDEKICK_RULE
    OIDC_RULE --> AZUREAD
    AZUREAD -->|"OIDC validate"| SECRET
    SECRET --> EXEC_ROLE

    ECS_SERVICE_APP --> ECS_TD_APP
    ECS_SERVICE_WORKER --> ECS_TD_WORKER
    ECS_TD_APP --> ECR_REPO
    ECS_TD_WORKER --> ECR_REPO
    ECS_SERVICE_APP --> ECS_AUTOSCALE
    ECS_SERVICE_WORKER --> ECS_AUTOSCALE

    ECS_TD_APP --> EFS_FS
    ECS_TD_APP --> RDS_INSTANCE
    ECS_TD_APP --> REDIS
    ECS_TD_APP --> TASK_ROLE
    ECS_TD_APP --> EXEC_ROLE

    ECS_CLUSTER --> ECS_SERVICE_APP
    ECS_CLUSTER --> ECS_SERVICE_WORKER
    ECS_CLUSTER --> ECS_SERVICE_OTHER

    LAMBDA_SCALER --> ECS_SERVICE_APP
    LAMBDA_SCALER --> ECS_SERVICE_WORKER
    LAMBDA_SCALER --> ASG

    SCHEDULER_SHUT --> LAMBDA_SCALER
    SCHEDULER_START --> LAMBDA_SCALER

    SNS_TOPIC --> SNS_EMAIL
    ALARM_CPU --> SNS_TOPIC
    ALARM_RAM --> SNS_TOPIC
    ALARM_COUNT --> SNS_TOPIC
    KMS_KEY --> SNS_TOPIC

    LAUNCH_TEMPLATE --> AMI
    LAUNCH_TEMPLATE --> KEYPAIR
    LAUNCH_TEMPLATE --> EBS
    LAUNCH_TEMPLATE --> INSTANCE_PROFILE
    ASG --> LAUNCH_TEMPLATE
    CAPACITY_PROVIDER --> ASG

    EFS_FS --> EFS_AP
    EFS_FS --> EFS_MT_1
    EFS_FS --> EFS_MT_2
    EFS_FS --> EFS_BACKUP
    EFS_MT_1 --> PRIVATE_SUBNETS
    EFS_MT_2 --> PRIVATE_SUBNETS

    RDS_INSTANCE --> RDS_PASSWORD
    RDS_INSTANCE --> RDS_SG
    RDS_INSTANCE --> RDS_SUBNET
    RDS_INSTANCE --> RDS_PARAM

    GITHUB --> BUILD
    GITHUB --> PLAN
    GITHUB --> DEPLOY
    GITHUB --> DESTROY

    ALB --> WAF
    ALB_MOD --> ALB
    ACM_ROOT --> ALB
    ACM_WILDCARD --> ALB
    ACM_VALIDATION --> ACM_ROOT
    ACM_VALIDATION --> ACM_WILDCARD

    ECS_SG --> ALB
    EFS_SG --> EFS_MT_1
    EFS_SG --> EFS_MT_2

    RDS_SG --> RDS_INSTANCE

    VPC --> PRIVATE_SUBNETS
    VPC --> PUBLIC_SUBNETS
```

## 服务统计

| 类别 | 数量 | 服务列表 |
|------|------|----------|
| Route53 | 4 | Hosted Zone, A Records (主+分), NS Delegation |
| ACM | 3 | 根证书, 通配符证书, 验证 |
| ALB (含外部模块) | 3 | ALB Module, ALB, WAF |
| ALB 路由 | 5 | HTTPS Listener, Target Groups (主+分), OIDC Rule, Static Rules |
| ECS | 6 | Cluster, Service×3, TaskDef×3, Autoscaling, CapacityProvider |
| EC2 (可选) | 6 | Launch Template, ASG, AMI, Key Pair, EBS, Instance Profile |
| ECR | 1 | ECR Repository |
| EFS | 5 | FileSystem, AccessPoint, MountTarget×2, BackupPolicy |
| RDS | 6 | Instance, Subnet Group, Parameter Group, Password, Snapshot ID, SG |
| Redis | 2 | Cluster, Subnet Group |
| Security Groups | 3 | ECS SG, EFS SG, ECS Egress |
| IAM | 4 | TaskRole, ExecutionRole, LambdaRole, SchedulerRole |
| Secrets | 1 | Azure AD Secret |
| KMS | 1 | SNS KMS Key |
| SNS | 2 | Topic, Email Subscription |
| CloudWatch | 5 | 2×Log Group, 3×Alarm |
| EventBridge | 2 | Shutdown Scheduler, Restart Scheduler |
| Lambda | 1 | Scaler Function |
| GitHub Actions | 6 | Build, Plan, Deploy, Destroy, ECS Check, ECR Findings |
| **合计** | **~55** | |
