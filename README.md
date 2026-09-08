# Atos Graduation Project — Cloud-Native GitOps & CI/CD Platform

Production-grade deployment and operations platform for the **Spring PetClinic** microservices application on **Amazon Elastic Kubernetes Service (EKS)**, automated through **Terraform**, **Jenkins Templating Engine (JTE)**, **Argo CD (App-of-Apps)**, **Argo Rollouts (Canary Progressive Delivery)**, **Karpenter**, and **Prometheus SRE Observability**.

---

## 1. Architectural Overview

The platform implements an automated GitOps delivery workflow and zero-trust private infrastructure model:

```
+---------------------------------------------------------------------------------------------------------+
|                                           AWS Cloud (us-east-1)                                         |
|                                                                                                         |
|  +--------------------+      +-----------------------+      +----------------------------------------+  |
|  |     Developer      | ---> |  Jenkins CI / JTE     | ---> |  Amazon ECR Repositories               |  |
|  | (Git Push / PR)    |      | (Maven, Sonar, Trivy) |      | (spring-petclinic:dev/test/prod tags)  |  |
|  +--------------------+      +-----------------------+      +----------------------------------------+  |
|                                                                                 |                       |
|                                                                                 v                       |
|  +-------------------------------------------------------------+    +--------------------------------+  |
|  | Git Repository (Single Source of Truth)                     |    | Argo CD Image Updater          |  |
|  | - helm/petclinic/values-*.yaml (Image tags written back)     | <- | (Polls ECR, Git Write-Back)   |  |
|  +-------------------------------------------------------------+    +--------------------------------+  |
|           |                                                                                             |
|           v                                                                                             |
|  +---------------------------------------------------------------------------------------------------+  |
|  | Private Amazon EKS Cluster 1.31 (atos-eks-cluster)                                                |  |
|  |                                                                                                   |  |
|  |  +-----------------------+        +--------------------------+        +------------------------+  |  |
|  |  | Argo CD (App-of-Apps) | -----> | Argo Rollouts Controller | -----> | Karpenter Autoscaler   |  |  |
|  |  | (Root Seed -> Apps)   |        | (5-Step Canary Analysis) |        | (Direct EC2 Provision) |  |  |
|  |  +-----------------------+        +--------------------------+        +------------------------+  |  |
|  |                                                |                                                  |  |
|  |                                                v                                                  |  |
|  |                                   +--------------------------+                                    |  |
|  |                                   | Workloads (dev/test/prod)|                                    |  |
|  |                                   | AWS ALB Ingress -> Pods  |                                    |  |
|  |                                   +--------------------------+                                    |  |
|  +---------------------------------------------------------------------------------------------------+  |
|                                                                                                         |
+---------------------------------------------------------------------------------------------------------+
```

---

## 2. Repository Layout

```text
AtosGraduationProject/
├── application/             # Spring Boot 3 source code, Dockerfile, and unit tests
├── infra/                   # Terraform IaC modules (VPC, EKS, Karpenter, IAM, Bastion)
├── helm/                    # Parameterized Spring PetClinic Helm chart and environment values
│   └── petclinic/
│       ├── values-dev.yaml
│       ├── values-test.yaml
│       └── values-prod.yaml
├── gitops/                  # Declarative Argo CD manifests & lifecycle automation scripts
│   ├── bootstrap.sh         # One-time cluster seeding script
│   ├── teardown.sh          # Cascading teardown and resource cleanup script
│   ├── root-application.yaml# App-of-Apps root seed
│   ├── platform/            # Core controllers (Karpenter, Prometheus, Rollouts, Ingress)
│   ├── projects/            # Argo CD project RBAC boundaries
│   └── workloads/           # Application environment sync definitions
└── docs/                    # Complete production engineering documentation
    ├── README.md            # Architecture index, component matrix & known limitations
    ├── infrastructure.md    # VPC networking, private EKS, Karpenter & Terraform specs
    ├── application.md       # Spring Boot 3, Java 17 Temurin, Actuator & Micrometer
    ├── helm.md              # Chart hierarchy, Rollout vs Deployment, ALB Ingress
    ├── gitops.md            # App-of-Apps, promotion cycle & Argo Rollouts canary
    ├── cicd-governance.md   # Jenkins JTE pipeline architecture & security gates
    ├── sre-observability.md # 99.9% SLO formulation, Multi-Burn-Rate alerting & PromQL
    ├── future-roadmap-and-improvements.md # 12 Blueprints for future enhancements
    ├── decisions/           # Architecture Decision Records (ADRs 001 to 007)
    └── troubleshooting/     # Central Operational Diagnostics & Runbooks (01 to 09)
```

---

## 3. Prerequisites & Tooling

Before provisioning the platform, verify that the following CLI binaries are installed on your administration workstation:

| Tool | Version Requirement | Purpose |
| :--- | :--- | :--- |
| **AWS CLI** | `v2.15+` | Cloud resource authentication and EKS kubeconfig generation |
| **Session Manager Plugin** | Latest | Enables encrypted tunneling to the private Bastion host |
| **Terraform** | `>= 1.5.0` | Provisioning AWS VPC, EKS, KMS, and IAM infrastructure |
| **kubectl** | `v1.31+` | Kubernetes cluster inspection and workload management |
| **Helm** | `v3.12+` | Kubernetes package management and Argo CD bootstrap |
| **Git** | `v2.40+` | Version control and GitOps repository synchronization |

---

## 4. Manual Credentials & Configuration Checklist

To initialize this project from scratch, specific cloud credentials, secrets, and tool configurations must be set up manually prior to deployment:

### 4.1 AWS Account Setup
1. **IAM Identity / AWS CLI Profile**:
   Configure local credentials with administrative access to target AWS Account (`069089526123` or your account):
   ```bash
   aws configure
   ```
2. **Terraform S3 State Storage**:
   Verify or create the S3 bucket configured in `infra/providers.tf` with object locking enabled:
   ```bash
   aws s3api create-bucket \
     --bucket petclinic-app-tfstate-069089526123-us-east-1-an \
     --region us-east-1
   ```
### 4.1 AWS Account Setup & Prerequisites
1. **IAM Identity / AWS CLI Profile**:
   Configure local credentials with administrative access to the target AWS Account (`069089526123` or your account):
   ```bash
   aws configure
   ```
2. **Terraform S3 State Storage**:
   Verify or create the S3 bucket configured in `infra/providers.tf` with object locking enabled:
   ```bash
   aws s3api create-bucket \
     --bucket petclinic-app-tfstate-069089526123-us-east-1-an \
     --region us-east-1
   ```
3. **Single Amazon ECR Repository**:
   The platform uses a **single ECR repository** with immutable environment-specific tag prefixes:
   - Repository Name: `atos-petclinic-app` (or `petclinic-project/petclinitc-app`)
   - The repository is automatically provisioned via `infra/ecr.tf` with push-scanning and lifecycle retention policies.
4. **ACM SSL/TLS Certificate**:
   Request or import a public ACM certificate in `us-east-1` for your application domain to terminate HTTPS on the AWS Application Load Balancers:
   - Certificate ARN is referenced in `helm/petclinic/values-test.yaml` and `values-prod.yaml` (`alb.ingress.kubernetes.io/certificate-arn`).

---

### 4.2 Secrets Management in AWS Secrets Manager (ESO Synchronization)
This project **does not require manual `kubectl apply` for secrets**. All sensitive credentials are stored centrally in **AWS Secrets Manager** and dynamically synchronized into the cluster by the **External Secrets Operator (ESO)** using **EKS Pod Identity** (`atos-eks-cluster-external-secrets-role`).

Before bootstrapping the cluster, create the following secrets in AWS Secrets Manager:

#### 1. Argo CD Git Write-Back Secret (`atos/petclinic/git-creds`)
Required for Argo CD and Argo CD Image Updater to commit and push updated image tags to GitHub:
```bash
aws secretsmanager create-secret \
  --name "atos/petclinic/git-creds" \
  --description "GitHub credentials for Argo CD Git write-backs" \
  --secret-string '{"username":"<YOUR_GITHUB_USERNAME>","token":"<YOUR_GITHUB_PERSONAL_ACCESS_TOKEN>"}' \
  --region us-east-1
```
*How it works*: The `ExternalSecret` manifest in [`gitops/platform/image-updater/git-creds-secret.yaml`](file:///home/devops/Atos/AtosGraduationProject/gitops/platform/image-updater/git-creds-secret.yaml) reads this secret and creates the Kubernetes Secret `repo-atosgraduationproject` with label `argocd.argoproj.io/secret-type: repository` inside the `argocd` namespace automatically.

#### 2. Workload Database Secrets
Create MySQL database connection secrets for each target environment:
- `atos/petclinic/dev/mysql`
- `atos/petclinic/test/mysql`
- `atos/petclinic/prod/mysql`

Example:
```bash
aws secretsmanager create-secret \
  --name "atos/petclinic/dev/mysql" \
  --secret-string '{"MYSQL_USER":"petclinic","MYSQL_PASSWORD":"<SECURE_PASSWORD>","MYSQL_URL":"jdbc:mysql://<RDS_HOST>:3306/petclinic"}' \
  --region us-east-1
```
*How it works*: The Helm chart's [`templates/externalsecret.yaml`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/templates/externalsecret.yaml) maps these directly to native Kubernetes Secrets in `petclinic-dev`, `petclinic-test`, and `petclinic-prod`.

---

### 4.3 Jenkins CI Server Configuration
If deploying or configuring the Jenkins CI controller, install the required plugins and configure credentials:

#### Required Jenkins Plugins
Install the following plugins via **Manage Jenkins $\rightarrow$ Plugins**:
- `Jenkins Templating Engine (JTE)` (`templating-engine`) — Governance and modular step libraries.
- `SonarQube Scanner` (`sonar`) — Static code quality and test coverage analysis.
- `Docker Pipeline` (`docker-workflow`) & `Docker CLI` — Container builds and image packaging.
- `Pipeline: AWS Steps` (`pipeline-aws`) — AWS STS role assumption and ECR interactions.
- `Git` & `GitHub Branch Source` — SCM checkout, multibranch scanning, and Git tagging.
- `Pipeline Stage View` / `Blue Ocean` — Stage visualization.

#### Required Credentials in Jenkins
Configure the following exact credential IDs under **Manage Jenkins $\rightarrow$ Credentials**:

| Credential ID | Type | Description |
| :--- | :--- | :--- |
| `petclinic-aws-credentials` | AWS Credentials | IAM Access Key / Secret Key used by JTE `aws` library to assume `JenkinsTerraformRole` |
| `petclinic-sonar-cred` | Secret text | SonarQube authentication token for code quality gates |
| `gitops-repo-push-token` | Secret text / Username & Password | GitHub Personal Access Token (`repo` scope) for Git release tagging |
| `petclinic-tfvars` | Secret file | Secret `terraform.tfvars` file injected into the Terraform pipeline |

#### Global Tools Configuration
Configure under **Manage Jenkins $\rightarrow$ Tools**:
- **JDK**: Eclipse Temurin 17 (`JDK-17`).
- **Maven**: Maven 3.9+ (`Maven-3.9`).
- **Docker**: Default Docker installation on the host or agent.
- **SonarQube Server**: Configured under **System Configuration $\rightarrow$ SonarQube servers** (`http://localhost:9000` or server endpoint).

---

## 5. Deployment Guide (Step-by-Step)

### Step 1: Provision Infrastructure with Terraform
1. Navigate to the `infra/` directory:
   ```bash
   cd infra
   ```
2. Initialize Terraform and download provider plugins:
   ```bash
   terraform init
   ```
3. Generate and review the speculative execution plan:
   ```bash
   terraform plan -out=tfplan
   ```
4. Apply the infrastructure:
   ```bash
   terraform apply tfplan
   ```
5. Retrieve outputs (VPC ID, Cluster Name, Bastion Instance ID):
   ```bash
   terraform output
   ```

---

### Step 2: Access the Private EKS Cluster
The EKS API server endpoint is private (`endpoint_public_access = false`). Connect via the AWS Systems Manager (SSM) Bastion host:

```bash
# Start an SSM session with the Bastion EC2 instance
aws ssm start-session --target <BASTION_INSTANCE_ID>

# Once logged into the Bastion, update kubeconfig:
aws eks update-kubeconfig --name atos-eks-cluster --region us-east-1

# Verify API server access:
kubectl get nodes
```

---

### Step 3: Bootstrap Argo CD and Platform Components
From your workstation (or from the Bastion host with cluster connectivity):

1. Execute the one-time bootstrap script:
   ```bash
   chmod +x gitops/bootstrap.sh
   ./gitops/bootstrap.sh
   ```
2. **What the script executes**:
   - Updates local `kubeconfig` for cluster `atos-eks-cluster`.
   - Creates the `argocd` namespace.
   - Installs Argo CD Helm Chart (`v10.6.0`) with a LoadBalancer service.
   - Applies `gitops/root-application.yaml` (the App-of-Apps seed).
3. **App-of-Apps Automated Cascading Provisioning**:
   - The Root application synchronizes:
     - `platform/`: Karpenter Autoscaler, AWS Load Balancer Controller, Prometheus & Grafana stack, Metrics Server, Argo Rollouts controller, External Secrets Operator (ESO), and Argo CD Image Updater.
     - Once ESO starts, it assumes the Pod Identity role, reads `atos/petclinic/git-creds` from AWS Secrets Manager, and generates the `repo-atosgraduationproject` secret.
     - `workloads/`: Spring PetClinic deployments in `petclinic-dev`, `petclinic-test`, and `petclinic-prod`.
4. **Retrieve Initial Argo CD Admin Password**:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
   ```
5. **Access Argo CD UI**:
   - Via LoadBalancer URL: Check `kubectl get svc argocd-server -n argocd`.
   - Via local port-forwarding:
     ```bash
     kubectl port-forward svc/argocd-server -n argocd 8080:80 --address 0.0.0.0
     ```
     Access at `http://localhost:8080` (User: `admin`).

---

### Step 4: Run Application CI/CD Pipeline
1. In Jenkins, create a pipeline pointing to `application/` using the JTE pipeline template (`pipelines_templates/AtosGradProj/app_ci/Jenkinsfile`).
2. Trigger the pipeline or push code to `main`.
3. The pipeline runs:
   - **Maven Compile & Unit Test**: Generates JaCoCo execution data.
   - **SonarQube Quality Gate**: Requires $\ge 80\%$ test coverage and zero critical bugs.
   - **Trivy Vulnerability Scanner**: Fails on `HIGH` or `CRITICAL` CVEs.
   - **Docker Image Build & Push**: Tags and uploads image to the single AWS ECR repository with tag `dev-${GIT_SHORT_SHA}`.
4. **GitOps Synchronization & Canary Deployment**:
   - Argo CD Image Updater polls ECR every 2 minutes.
   - On new `dev-*` tag discovery, it writes the tag back to `gitops/workloads/dev/values.yaml` in Git.
   - Argo CD syncs the change into `petclinic-dev`.
   - On release tags (`v*-rc` or `v*`), Jenkins retags the image manifest in ECR without rebuilding (`test-${GIT_TAG}` or `prod-${GIT_TAG}`).
   - In `test` and `prod`, Argo Rollouts triggers a 5-step canary deployment (20% $\rightarrow$ 40% $\rightarrow$ 60% $\rightarrow$ 80% $\rightarrow$ 100%) with automated Prometheus metric analysis.

---

## 6. Teardown & Decommissioning Guide

To terminate the platform and prevent ongoing AWS charges, execute the clean-up steps in strict sequence:

### Step 1: Cascading Workload & Platform Teardown
1. Run the automated GitOps teardown script:
   ```bash
   chmod +x gitops/teardown.sh
   ./gitops/teardown.sh --all
   ```
2. **What the script executes**:
   - Deletes `root` application in `argocd`.
   - Argo CD cascades deletion down to all child applications, triggering Kubernetes to delete:
     - AWS Application Load Balancers (ALB ingress resources).
     - PersistentVolumeClaims (AWS EBS storage volumes).
     - Workload pods and namespaces (`petclinic-dev`, `petclinic-test`, `petclinic-prod`).
     - Core controllers (Karpenter, AWS Load Balancer Controller).
   - Waits in a loop until all AWS cloud resources and applications are terminated.
   - Uninstalls Argo CD Helm release and removes the `argocd` namespace.

> [!IMPORTANT]
> Always allow `gitops/teardown.sh` to finish completely before destroying Terraform infrastructure. If Terraform is destroyed while Kubernetes Ingress resources still exist, AWS Application Load Balancers and Security Groups become orphaned in AWS, blocking VPC deletion.

---

### Step 2: Destroy Cloud Infrastructure with Terraform
Once all Kubernetes-provisioned AWS load balancers and volumes have been removed:

1. Navigate to `infra/`:
   ```bash
   cd infra
   ```
2. Execute the Terraform destroy command:
   ```bash
   terraform destroy -auto-approve
   ```
3. Terraform cleanly removes the EKS control plane, managed node groups, KMS keys, Bastion host, and 3-AZ VPC.

---

## 7. Complete Documentation Index

For detailed architectural designs, deep-dive specifications, runbooks, and decisions, reference the dedicated technical files in `docs/`:

| Document | Description |
| :--- | :--- |
| [**docs/README.md**](docs/README.md) | Central documentation index, component matrix, and known limitations |
| [**docs/infrastructure.md**](docs/infrastructure.md) | AWS EKS 1.31, 3-AZ VPC CIDR topology, KMS encryption, Karpenter & Terraform |
| [**docs/application.md**](docs/application.md) | Spring Boot 3, Java 17 Temurin Alpine, cgroup JVM limits, and Actuator metrics |
| [**docs/helm.md**](docs/helm.md) | Helm chart hierarchy, Rollout/Deployment abstraction, ALB Ingress, and HPA |
| [**docs/gitops.md**](docs/gitops.md) | Argo CD App-of-Apps, multi-environment promotion, and 5-step Canary Rollouts |
| [**docs/cicd-governance.md**](docs/cicd-governance.md) | Jenkins JTE architecture, step catalog, SonarQube gates, and ECR retagging |
| [**docs/sre-observability.md**](docs/sre-observability.md) | 99.9% SLO formulation, Google SRE Multi-Burn-Rate alerting, and PromQL runbook |
| [**docs/future-roadmap-and-improvements.md**](docs/future-roadmap-and-improvements.md) | 12 technical implementation blueprints for future enhancements and FinOps |
| [**docs/decisions/ (ADRs)**](docs/decisions/README.md) | Architecture Decision Records (ADRs 001 through 007) |
| [**docs/troubleshooting/ (Runbooks)**](docs/troubleshooting/README.md) | Operational Diagnostics & Runbooks (01 through 09) |
