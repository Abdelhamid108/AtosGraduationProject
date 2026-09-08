# Spring PetClinic Platform Documentation

This repository contains the infrastructure, packaging, continuous integration, GitOps continuous delivery, and reliability engineering setup for Spring PetClinic on Amazon Web Services (AWS).

---

## 1. End-to-End System Architecture

```
                                      [ Internet Clients ]
                                                │
                                       [ Route 53 / DNS ]
                                                │
                                  [ AWS Application Load Balancer ]
                             (Port 80 -> 443 HTTP 301 Redirect, ACM TLS)
                                                │
┌───────────────────────────────────────────────▼───────────────────────────────────────────────┐
│ AWS Virtual Private Cloud (10.0.0.0/16) - 3 Availability Zones (us-east-1a, 1b, 1c)          │
│                                                                                               │
│  [Tier 1: Public Subnets (10.0.1.0/24 - 10.0.3.0/24)]                                         │
│  ├── Bastion Host (t3.micro / Amazon Linux 2023 / AWS SSM Session Manager / IMDSv2 Enforced)  │
│  ├── Internet-Facing ALB Listener Pool (alb.ingress.kubernetes.io/target-type: ip)             │
│  └── Single NAT Gateway (Elastic IP / Outbound Internet Egress)                               │
│                                                                                               │
│  [Tier 2: Private Subnets (10.0.10.0/24 - 10.0.30.0/24)]                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Amazon EKS Cluster 1.31 (Private API Server, KMS Envelope Encryption, EKS Access Entries)│  │
│  │                                                                                         │  │
│  │  [Platform Infrastructure Services]                                                     │  │
│  │  ├── Core Networking: AWS VPC CNI (Prefix Delegation), CoreDNS, Kube-Proxy              │  │
│  │  ├── Ingress Controller: AWS Load Balancer Controller (EKS Pod Identity)                │  │
│  │  ├── Compute Elasticity: Karpenter v1.14.1 (Direct EC2 Fleet APIs / SQS Interruption)   │  │
│  │  ├── Secrets Management: External Secrets Operator (AWS Secrets Manager Sync)          │  │
│  │  ├── Observability: Prometheus Operator, Alertmanager, Grafana Sidecar Dashboards       │  │
│  │  └── Progressive Delivery: Argo CD Controller, Image Updater, Argo Rollouts Controller  │  │
│  │                                                                                         │  │
│  │  [Tenant Workload Environments]                                                         │  │
│  │  ├── petclinic-dev:  Continuous Delivery (Deployment / Image Updater regexp: ^dev-.*$)  │  │
│  │  ├── petclinic-test: Release Candidate Gating (Canary Rollout / PromQL Analysis)       │  │
│  │  └── petclinic-prod: Production Release Gating (5-Step Canary / 99.9% SLO Monitoring)   │  │
│  │                                                                                         │  │
│  │  [Data Layer]                                                                           │  │
│  │  └── In-Cluster MySQL StatefulSet (Amazon EBS CSI Driver / Persistent Volume Claims)     │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Technology Stack & Component Matrix

| Layer | Component | Specification | Technical Role |
| :--- | :--- | :--- | :--- |
| **Cloud Platform** | Amazon Web Services | Region: `us-east-1` | 3-AZ VPC (`10.0.0.0/16`), NAT Gateway, Internet Gateway, KMS, S3, ACM. |
| **IaC Engine** | HashiCorp Terraform | `>= 1.5.0` (AWS Provider `~> 6.0`) | Modular infrastructure with encrypted remote S3 backend and native `.tflock` concurrency control. |
| **Kubernetes** | Amazon EKS | Version `1.31` | Private control plane endpoint, audit log streaming, and declarative EKS Access Entries API. |
| **Compute Scaling**| AWS Karpenter | Version `1.14.1` | High-performance direct EC2 node provisioning, Spot interruption queues (SQS/EventBridge), and consolidation. |
| **IAM Auth** | EKS Pod Identity | Native Add-On | Replaces legacy IRSA. Grants AWS credentials to pods via static `pods.eks.amazonaws.com` trust policies. |
| **Application** | Spring PetClinic | Spring Boot 3.3.x / Java 17 | Multi-profile (`h2` / `mysql`), HikariCP pooling, Actuator probes, and Micrometer Prometheus metrics. |
| **Container** | Docker | Alpine Linux Temurin 17 | Hardened multi-stage build, non-root execution (`appuser:appgroup` UID 1001), `-XX:MaxRAMPercentage=75.0`. |
| **Packaging** | Helm | Version `v3.x` | Parameterized single chart abstracting `Deployment` vs. `Rollout` controllers, HPA, PDB, and ALB Ingress. |
| **CI Engine** | Jenkins with JTE | Jenkins Templating Engine | Modular step libraries (`/home/devops/Atos/JTE`), SonarQube quality gates ($\ge 80\%$), and Trivy CVE scanning. |
| **Continuous Delivery**| Argo CD | Version `v2.x` | App-of-Apps architectural pattern, automated GitOps self-healing, and automated ECR Image Updater. |
| **Progressive Rollout**| Argo Rollouts | Version `v1.x` | 5-step canary release automation (20% to 100%) with real-time PromQL background regression analysis. |
| **Observability** | Prometheus & Grafana| kube-prometheus-stack | 99.9% Availability SLO, Multi-Window Multi-Burn-Rate alerting rules (14.4x / 6x), and Golden Signals. |

---

## 3. Comprehensive Documentation Directory

The documentation is organized into focused, single-file technical guides per domain, supported by Architecture Decision Records (ADRs) and Operational Troubleshooting Runbooks:

### Core Technical Guides
1. [**Infrastructure & Cloud Architecture (`docs/infrastructure.md`)**](infrastructure.md)
   AWS 3-AZ VPC networking, subnet CIDR tables, zero-trust Bastion host via SSM Session Manager, private EKS 1.31 control plane, KMS envelope encryption, EKS Access Entries, EKS Pod Identity associations, Karpenter compute elasticity, and native S3 state locking.
2. [**Application Engineering & Container Runtime (`docs/application.md`)**](application.md)
   Spring Boot 3 software architecture, hardened Alpine Temurin 17 Dockerfile, JVM container memory ergonomics (`-XX:+UseContainerSupport`, 75% heap ceiling), database profiles (`h2` vs `mysql`), zero-downtime graceful shutdown sequence (30s drain), and custom Micrometer counter instrumentation.
3. [**Kubernetes Packaging & Helm Engineering (`docs/helm.md`)**](helm.md)
   Single-chart parameterized design, workload abstraction toggling between standard `Deployment` and `Rollout`, AWS Load Balancer Controller Ingress annotations (Target-Type IP, HTTPS redirection, ACM certificate), PodDisruptionBudget (`minAvailable: 1`), HPA, and External Secrets Operator integration.
4. [**GitOps Operating Model & Progressive Delivery (`docs/gitops.md`)**](gitops.md)
   Argo CD App-of-Apps pattern, project RBAC boundaries (`platform-project` vs `workloads-project`), multi-environment promotion lifecycle (`dev` $\rightarrow$ `test` $\rightarrow$ `prod`), Argo CD Image Updater polling and Git write-back mechanics, and Argo Rollouts 5-step canary deployment with background metric analysis.
5. [**CI/CD Governance & Security Gates (`docs/cicd-governance.md`)**](cicd-governance.md)
   Jenkins Templating Engine (JTE) architecture, modular step library catalog in `/home/devops/Atos/JTE`, SonarQube quality gate enforcement ($\ge 80\%$ test coverage), Trivy filesystem CVE scanning, AWS ECR batch retagging, and S3 JSON distributed version registry.
6. [**SRE Observability, SLO Framework & Error Budget Alerting (`docs/sre-observability.md`)**](sre-observability.md)
   99.9% Availability SLO mathematical formulation (rolling 30-day window, 43.2 minutes error budget), Google SRE Multi-Window Multi-Burn-Rate alerting math (14.4x fast burn, 6x slow burn), Prometheus recording rules, and Grafana dashboards (SLO Error Budget & Golden Signals).
7. [**Future Roadmap, Technical Debt & Unimplemented Improvements (`docs/future-roadmap-and-improvements.md`)**](future-roadmap-and-improvements.md)
   Detailed, step-by-step implementation blueprints prioritized by impact and blast-radius: Prod vs. Non-Prod cluster isolation, GitHub governance & branch/tag RBAC with HMAC webhooks, automated pipeline canary rollback hooks, scheduled infrastructure drift detection, AWS WAF & Zero-Trust NetworkPolicies, ephemeral sandbox `terraform apply` validation, ephemeral PR preview environments via Argo CD ApplicationSet, dynamic Kubernetes/Fargate Jenkins agents, Infracost FinOps PR guardrails, Prometheus long-term storage (AWS AMP), automated load/chaos testing, AWS Client VPN, and empirical resource rightsizing.

---

### Architecture Decision Records (`docs/decisions/`)
Documented in accordance with standard ADR specifications:
- [**ADR Index & Decision Framework**](decisions/README.md)
- [**ADR-001: Karpenter vs. Kubernetes Cluster Autoscaler**](decisions/adr-001-karpenter-vs-cluster-autoscaler.md)
- [**ADR-002: EKS Pod Identity vs. IAM Roles for Service Accounts (IRSA)**](decisions/adr-002-eks-pod-identity-vs-irsa.md)
- [**ADR-003: Argo Rollouts Canary vs. Standard Kubernetes Rolling Updates**](decisions/adr-003-argo-rollouts-canary-vs-native-rolling-update.md)
- [**ADR-004: Jenkins JTE Governance vs. Monolithic Jenkinsfiles**](decisions/adr-004-jenkins-jte-governance-vs-monolithic-jenkinsfiles.md)
- [**ADR-005: Deterministic IAM Role Naming Strategy for GitOps**](decisions/adr-005-deterministic-iam-naming-strategy.md)
- [**ADR-006: Argo CD Image Updater vs. CI-Driven Deployments**](decisions/adr-006-argocd-image-updater-vs-ci-git-writeback.md)
- [**ADR-007: Trunk-Based Branching & Tag-Driven Promotion Strategy**](decisions/adr-007-trunk-based-branching-and-tag-driven-promotion.md)

---

### Operational Runbooks & Incident Troubleshooting (`docs/troubleshooting/`)
Actionable diagnostic runbooks covering observed production failure scenarios:
- [**Runbook Index & Incident Lookup Matrix**](troubleshooting/README.md)
- [**Runbook 01: Private Control Plane & Zero-Trust Bastion Access**](troubleshooting/01-private-cluster-control-plane-and-bastion-architecture.md)
- [**Runbook 02: EKS Pod Identity & Storage Addon Lifecycle**](troubleshooting/02-eks-pod-identity-and-addon-lifecycle-architecture.md)
- [**Runbook 03: Kubernetes Declarative Access Entries & RBAC**](troubleshooting/03-kubernetes-rbac-and-declarative-access-entries-architecture.md)
- [**Runbook 04: Multi-AZ Subnet Topology & ALB Auto-Discovery**](troubleshooting/04-multi-az-subnet-topology-and-load-balancer-discovery.md)
- [**Runbook 05: Temporary Credentials & Dynamic Role Delegation**](troubleshooting/05-temporary-credentials-and-dynamic-role-delegation.md)
- [**Runbook 06: Karpenter Compute Elasticity & Spot Interruption**](troubleshooting/06-karpenter-autoscaling-and-spot-interruption-architecture.md)
- [**Runbook 07: ACM Certificates & ALB HTTPS Redirection**](troubleshooting/07-acm-certificates-and-https-redirection.md)
- [**Runbook 08: PrometheusRule CoreOS Webhook Validation Denials**](troubleshooting/08-prometheus-rule-validation-and-webhook-denials.md)
- [**Runbook 09: Argo Rollouts Canary Degradation & Emergency Rollback**](troubleshooting/09-argo-rollouts-canary-degradation-and-rollback.md)
- [**Runbook 10: Argo CD Sync Waves, CRD Ordering & Dependency Race Conditions**](troubleshooting/10-argocd-sync-waves-and-crd-race-conditions.md)

---

## 4. Known Architectural Trade-offs, Limitations & Technical Debt

Every architectural choice involves trade-offs. Below are the known limitations, intentional trade-offs, and areas of technical debt in the current setup:

### 4.1 Single NAT Gateway (Cost vs. AZ Fault Tolerance)
- **Current Setup**: All private subnets across `us-east-1a`, `us-east-1b`, and `us-east-1c` route outbound internet traffic through a single NAT Gateway located in `us-east-1c` (`single_nat_gateway = true`).
- **Trade-off**: Saves AWS runtime costs (~$32/month vs. ~$96/month for 3 NAT Gateways).
- **Risk / Limitation**: If the `us-east-1c` availability zone suffers an AWS infrastructure outage, outbound internet egress fails for all private worker nodes across all 3 AZs. Nodes would be unable to pull images from public registries or reach external APIs until connectivity is restored.
- **Production Remedy**: For enterprise mission-critical workloads, set `single_nat_gateway = false` and `one_nat_gateway_per_az = true` in `infra/modules/vpc/main.tf`, or configure AWS VPC Endpoints for S3 and ECR to keep image pulls on the AWS private network.

### 4.2 In-Cluster MySQL StatefulSet vs. Managed Amazon RDS
- **Current Setup**: MySQL is deployed as an in-cluster Kubernetes `StatefulSet` with an Amazon EBS volume backed by the EBS CSI driver.
- **Trade-off**: Zero additional AWS managed service costs; simple local deployment model.
- **Risk / Limitation**: Lacks multi-AZ synchronous replication, automated point-in-time recovery (PITR), and automated failover. If the worker node hosting the MySQL pod crashes, Kubernetes must reschedule the pod on another node and reattach the EBS volume, causing 1 to 2 minutes of database unavailability.
- **Production Remedy**: Migrate persistence to Amazon Aurora MySQL Multi-AZ with automated snapshots and read replicas.

### 4.3 Argo CD Image Updater Polling Latency & Git Commit Volume
- **Current Setup**: Argo CD Image Updater polls Amazon ECR every 2 minutes and writes new image tags directly to `gitops/workloads/<env>/values.yaml` on branch `main`.
- **Trade-off**: Eliminates the need to grant Jenkins cluster admin access or Git push keys.
- **Risk / Limitation**: 
  1. Introduces up to a 2-minute delay between Jenkins pushing the image to ECR and the Git commit being created.
  2. Frequent continuous builds on `main` create a high volume of automated Git commits (`image.tag: dev-SHA`), cluttering the Git commit history.
- **Production Remedy**: Configure Amazon EventBridge to send ECR image push notifications via webhooks directly to the Image Updater controller to eliminate the polling delay, or write commits to a dedicated environment release branch instead of `main`.

### 4.4 Private Control Plane Operational Friction
- **Current Setup**: EKS API endpoint is strictly private (`endpoint_public_access = false`).
- **Trade-off**: Maximum network security; eliminates public internet vulnerability scans against the Kubernetes API server.
- **Risk / Limitation**: Operators cannot run `kubectl` from developer laptops or external networks without first establishing an AWS SSM Session Manager WebSocket tunnel through the Bastion host.
- **Production Remedy**: Establish an AWS Client VPN endpoint or AWS Direct Connect into the VPC for seamless corporate network access.

### 4.5 Karpenter CRD Bootstrap Race Condition
- **Current Setup**: The Karpenter Helm chart installs CRDs at sync-wave `0`, while `nodepool.yaml` installs `NodePool` and `EC2NodeClass` resources at sync-wave `1` within the same repository.
- **Risk / Limitation**: During a completely fresh, from-scratch cluster deployment, sync-wave ordering waits for the previous wave's pods to launch, not for the Kubernetes API server to fully register the new CRD schemas in etcd. Argo CD can momentarily report `no matches for kind NodePool`. The second sync resolves it automatically, but it is a known transient race during fresh cluster bootstrap.
- **Production Remedy**: Pre-install Karpenter CRDs via an initial cluster bootstrap script or isolate Karpenter into its own dedicated bootstrap Application.

### 4.6 In-Cluster Prometheus Local Storage
- **Current Setup**: Prometheus stores metric time-series data on a local EBS volume in the `monitoring` namespace with a 15-day retention policy.
- **Trade-off**: Self-contained observability stack requiring no external SaaS or managed service costs.
- **Risk / Limitation**: High request volume or high label cardinality can exhaust pod memory or disk space. If the Prometheus pod is recreated, historical data beyond the volume retention is lost.
- **Production Remedy**: Offload long-term metric storage to Amazon Managed Service for Prometheus (AMP) with S3 retention, or deploy Thanos with an S3 object storage sink.

### 4.7 Unhandled Problem: Git and Cluster Divergence on Canary Abort
- **The Problem**: When Image Updater detects a new image tag, it immediately writes `image.tag: v1.2.0` to `values.yaml` in Git. Argo Rollouts then starts a canary rollout. If the automated metric analysis fails, Argo Rollouts **aborts** and reverts traffic back to the old image (`v1.1.0`) in the cluster.
- **Why This is an Unhandled Flaw**:
  - The cluster is running `v1.1.0`.
  - Git still says `v1.2.0`.
  - **There is currently no automation in this project to revert the Git commit.**
  - Git is left in a lying state: anyone looking at the repository believes `v1.2.0` is running in production when it was actually aborted.
  - A human operator **must manually revert the Git commit or push a fix**. If an operator triggers an Argo CD hard-refresh or manual sync without checking, they risk re-triggering the failed rollout.
