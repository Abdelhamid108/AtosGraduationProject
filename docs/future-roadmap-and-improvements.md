# Future Roadmap, Technical Debt & Unimplemented Improvements

This document outlines the architectural enhancements, security hardening, testing pipelines, and operational improvements that were planned but could not be fully implemented in the current release. 

Each section provides the technical motivation, the current state, and step-by-step implementation procedures for future execution.

---

## Executive Prioritization Matrix

The initiatives below are ranked in descending order of **criticality, blast-radius reduction, and architectural impact**—prioritizing foundational security and integrity first, followed by release reliability, developer velocity, and operational fine-tuning.

| Rank | Initiative | Domain | Impact / Blast Radius | Complexity |
| :---: | :--- | :--- | :--- | :---: |
| **01** | [**Prod vs. Non-Prod Cluster & Network Isolation**](#1-prod-vs-non-prod-cluster--network-isolation) | Architecture / Security | **Critical** (Eliminates dev-to-prod compute & data spillover) | High |
| **02** | [**GitHub Governance: Branch Protection, Tag RBAC & HMAC Webhooks**](#2-github-governance-strict-branch-protection-tag-rbac--hmac-webhooks) | Supply Chain Security | **Critical** (Blocks unreviewed code & rogue production releases) | Medium |
| **03** | [**Pipeline Synchronization & Automated Canary Rollback Hooks**](#3-pipeline-synchronization--automated-canary-rollback-hooks) | Release Reliability | **Critical** (Resolves Git-vs-Cluster divergence on canary abort) | Medium |
| **04** | [**Automated Infrastructure Drift Detection & Reconciliation Jobs**](#4-automated-infrastructure-drift-detection--reconciliation-jobs) | IaC Governance | **High** (Detects out-of-band ClickOps & restores Git truth) | Medium |
| **05** | [**Web Application Firewall (AWS WAF) & Zero-Trust NetworkPolicies**](#5-web-application-firewall-aws-waf--zero-trust-networkpolicies) | Perimeter Security | **High** (Mitigates OWASP Top 10 & isolates pod namespaces) | Medium |
| **06** | [**Ephemeral Sandbox Infrastructure Provisioning (`terraform apply` Validation)**](#6-ephemeral-sandbox-infrastructure-provisioning-terraform-apply-validation) | IaC Quality | **High** (Guarantees pre-merge cloud API validation) | High |
| **07** | [**Ephemeral Preview Environments for Pull Requests (Argo CD ApplicationSet)**](#7-ephemeral-preview-environments-for-pull-requests-argo-cd-applicationset) | Developer Velocity | **High** (Eliminates shared-dev collision across feature PRs) | Medium |
| **08** | [**Ephemeral Jenkins Build Agents (Kubernetes / AWS Fargate)**](#8-ephemeral-jenkins-build-agents-kubernetes--aws-fargate) | CI Elasticity & FinOps | **Medium-High** (Removes static VM bottlenecks & idle costs) | Medium |
| **09** | [**Automated FinOps & Cloud Cost Guardrails (Infracost on Pull Requests)**](#9-automated-finops--cloud-cost-guardrails-infracost-on-pull-requests) | Cost Governance | **Medium** (Enforces pre-merge monthly cloud budget caps) | Low |
| **10** | [**Prometheus Long-Term Storage (AWS AMP / Thanos Remote-Write)**](#10-prometheus-long-term-storage-aws-amp--thanos-remote-write) | Observability | **Medium** (Preserves historical metric data beyond 15-day EBS) | Low |
| **11** | [**End-to-End Automated Testing Scenarios (k6 Load & Chaos Mesh)**](#11-end-to-end-automated-testing-scenarios-k6-load--chaos-mesh) | Reliability Testing | **Medium** (Validates HPA, Karpenter & PodDisruptionBudgets) | Medium |
| **12** | [**AWS Client VPN for Private Cluster Access**](#12-aws-client-vpn-for-private-cluster-access) | Operational DX | **Medium** (Replaces Bastion SSM WebSocket tunnel latency) | Medium |
| **13** | [**Resource Rightsizing & Tuning from Real Load Data**](#13-resource-rightsizing--tuning-from-real-load-data) | Performance / FinOps | **Optimization** (Maximizes Karpenter node bin-packing efficiency) | Low |

---

## 1. Prod vs. Non-Prod Cluster & Network Isolation

### 1.1 Motivation & Current State
- **Current State**: All environments (`dev`, `test`, `prod`) run inside a single Amazon EKS cluster (`atos-eks-cluster`), separated only by Kubernetes namespaces.
- **Limitation**: A misconfigured workload or runaway memory leak in `dev` can exhaust worker node CPU/memory or saturate cluster-wide CoreDNS/Kube-Proxy, directly degrading production availability. Furthermore, shared IAM OIDC providers create risk of accidental cross-environment credential exposure.
- **Target Goal**: Physical, hard multi-cluster separation:
  - `non-prod-eks-cluster`: Dedicated VPC hosting `dev`, `test`, and ephemeral PR environments.
  - `prod-eks-cluster`: Dedicated, highly restricted production VPC with isolated worker nodes, separate IAM boundaries, and strict ingress peering.

### 1.2 Implementation Steps
1. **Split Terraform Configurations**:
   Structure modular infrastructure into separate environment roots in `infra/`:
   ```text
   infra/
   ├── modules/            # Shared reusable modules (vpc, eks, iam, compute)
   └── environments/
       ├── non-prod/       # Terraform root for non-prod VPC & EKS
       └── prod/           # Terraform root for production VPC & EKS
   ```
2. **VPC Separation & Peering**:
   - Deploy non-prod in CIDR `10.1.0.0/16` and prod in CIDR `10.2.0.0/16`.
   - Disallow any cross-VPC peering routing between non-prod and prod. Only allow authorized monitoring or telemetry traffic through an AWS Transit Gateway with stateful security groups.
3. **IAM Boundary Isolation**:
   - Create completely disjoint IAM OIDC trust policies. Non-prod pods have zero IAM permissions to query production AWS Secrets Manager secrets, S3 buckets, or RDS databases.

---

## 2. GitHub Governance: Strict Branch Protection, Tag RBAC & HMAC Webhooks

### 2.1 Motivation & Current State
- **Current State**: Commits can be pushed directly to `main` without enforced peer reviews, and Git tags (`v*`, `v*-rc`) can be pushed by any developer with write access. Jenkins triggers pipelines via scheduled SCM polling or manual executions.
- **Limitation & Supply Chain Vulnerabilities**:
  1. **Direct Pushes Bypass Verification**: Direct pushes to `main` completely circumvent unit tests, SonarQube quality gates, Trivy container security scans, and peer architectural reviews.
  2. **Unauthorized Production Deployments**: Under the tag-driven promotion model ([ADR-007](decisions/adr-007-trunk-based-branching-and-tag-driven-promotion.md)), pushing a tag like `v1.2.0` automatically triggers Jenkins to retag the ECR image and triggers Argo CD to roll out a production canary. Without tag RBAC, any junior developer or compromised credential can deploy to production.
  3. **Polling Latency & Spoofing Risks**: Jenkins SCM polling introduces 2-to-5 minute build latencies and burns GitHub API rate limits. Conversely, unauthenticated webhooks are vulnerable to spoofing and replay attacks.
- **Target Goal**: Implement enterprise-grade GitHub governance:
  - Strict branch protection on `main` (no direct push, mandatory PR, peer approvals, required status checks, linear history).
  - Restricted Tag Protection rules and GitHub Releases RBAC limiting release tag creation (`v*`, `v*-rc`) exclusively to Tech Leads and Release Managers.
  - Event-driven GitHub-to-Jenkins webhooks with HMAC SHA-256 payload signature verification.

### 2.2 Implementation Steps
1. **Enforce Branch Protection on `main`**:
   Apply declarative branch protection via GitHub API or Terraform (`github_branch_protection`):
   ```hcl
   resource "github_branch_protection" "main" {
     repository_id = "AtosGraduationProject"
     pattern       = "main"

     enforce_admins = true # Administrators cannot bypass these rules

     required_pull_request_reviews {
       dismiss_stale_reviews           = true # Invalidate approvals on new commit
       require_code_owner_reviews      = true # CODEOWNERS must approve
       required_approving_review_count = 1    # Minimum 1 senior peer review
       require_last_push_approval      = true # Require re-approval on latest push
     }

     required_status_checks {
       strict = true # Branch must be fully up-to-date with main before merge
       contexts = [
         "jenkins/pr-build",
         "sonarqube/quality-gate",
         "security/trivy-scan",
         "finops/infracost-check"
       ]
     }

     allows_force_pushes = false
     allows_deletions    = false
     require_linear_history = true # Enforces clean, rebased/squashed Git history
   }
   ```

2. **Configure Mandatory `CODEOWNERS`**:
   Commit `.github/CODEOWNERS` to establish path-based review requirements:
   ```text
   # Global fallback reviewers
   *                      @Abdelhamid108

   # Infrastructure and cloud resources require DevOps Lead approval
   /infra/                @Abdelhamid108 @devops-leads

   # Kubernetes manifests & GitOps configurations require Platform Team approval
   /helm/                 @Abdelhamid108 @platform-engineers
   /gitops/               @Abdelhamid108 @platform-engineers

   # CI/CD pipeline definitions
   /Jenkinsfile           @Abdelhamid108 @devops-leads
   /pipelines_templates/  @Abdelhamid108 @devops-leads
   ```

3. **Enforce Tag Protection Rules & Release RBAC**:
   - In GitHub Settings $\rightarrow$ **Tags** $\rightarrow$ **Tag protection rules**:
     - Rule Pattern: `v*` (matches both `v*-rc` and `v*.*.*`).
     - Allowed Actors: Restrict to **Repository Admins** and the **`@release-managers`** team.
   - Configure a GitHub Environment named `production` requiring manual reviewer approvals before dispatching deployment events.
   - **Pipeline Guardrail**: Add a tag authenticity verification step in `pipelines_templates/AtosGradProj/app_ci/Jenkinsfile`:
     ```groovy
     stage('Verify Tag Authority') {
         when { buildingTag() }
         steps {
             script {
                 withCredentials([string(credentialsId: 'github-api-token', variable: 'GH_TOKEN')]) {
                     def tagger = sh(script: "git log -1 --format='%ae' ${TAG_NAME}", returnStdout: true).trim()
                     def response = sh(
                         script: """
                         curl -s -H "Authorization: token ${GH_TOKEN}" \
                           https://api.github.com/repos/Abdelhamid108/AtosGraduationProject/teams/release-managers/memberships/${tagger}
                         """,
                         returnStdout: true
                     )
                     if (!response.contains('"state": "active"')) {
                         error "Security Violation: User '${tagger}' is not authorized in @release-managers to cut production tag '${TAG_NAME}'."
                     }
                 }
             }
         }
     }
     ```

4. **Event-Driven GitHub-to-Jenkins Webhook with HMAC SHA-256**:
   - In GitHub repository Settings $\rightarrow$ **Webhooks** $\rightarrow$ **Add webhook**:
     - **Payload URL**: `https://jenkins.internal/github-webhook/`
     - **Content type**: `application/json`
     - **Secret**: Generate a cryptographically secure 64-character token (`openssl rand -hex 32`) and store it in Jenkins Credentials (`github-webhook-hmac-secret`).
     - **Events**: Select individual events:
       - `Pull requests` (triggers PR build, unit tests, SonarQube, Infracost).
       - `Pushes` (triggers `dev` build on merge to `main`).
       - `Releases` & `Tag creates` (triggers `test` or `prod` tag promotion).
   - **HMAC Verification**: Jenkins GitHub Plugin automatically validates the `X-Hub-Signature-256` header on all inbound webhook payloads against the shared HMAC secret. Any payload with a missing, mismatched, or altered signature is immediately dropped with HTTP 403 Forbidden.

---

## 3. Pipeline Synchronization & Automated Canary Rollback Hooks

### 3.1 Motivation & Current State
- **Current State**: The Jenkins CI pipeline pushes image tags to AWS ECR and terminates. Argo CD Image Updater detects the new image tag and commits it to `gitops/workloads/<env>/values.yaml`. Argo Rollouts then initiates the canary release.
- **The Unhandled Architectural Flaw**:
  - If the canary analysis fails in `test` or `prod` (e.g., HTTP 5xx error rate exceeds 1%), Argo Rollouts automatically **aborts** the rollout in the cluster and routes 100% of traffic back to the previous stable revision.
  - **However, Git still contains the failed image tag in `values.yaml`**.
  - This creates **Git-versus-Cluster divergence**: Git says version `v1.2.0` is active, but the cluster is running `v1.1.0`. A manual `argocd app sync` or controller restart will re-trigger the broken rollout.
- **Target Goal**: Connect Argo Rollouts notification webhooks back to a Jenkins automated reconciliation pipeline that creates an automated Git revert commit upon canary abort, restoring Git as the truthful source of truth.

### 3.2 Implementation Steps
1. **Configure Argo Rollouts Notification Webhook**:
   In `gitops/platform/argo-rollouts/values.yaml`, define a notification trigger on `on-rollout-aborted`:
   ```yaml
   notifications:
     triggers:
       trigger.on-rollout-aborted: |
         - when: rollout.status.phase == 'Degraded' or rollout.status.abort == true
           send: [jenkins-revert-webhook]
     templates:
       template.jenkins-revert-webhook: |
         webhook:
           jenkins-revert:
             method: POST
             path: /generic-webhook-trigger/invoke
             body: |
               {
                 "environment": "{{ .rollout.metadata.namespace }}",
                 "failed_tag": "{{ (index .rollout.spec.template.spec.containers 0).image }}",
                 "status": "ABORTED"
               }
   ```
2. **Automated Git Revert Jenkins Pipeline**:
   Deploy a Jenkins reconciliation job that checks out the repo, identifies the previous working image tag from git history, reverts the failed commit, and pushes the fix back to `main`:
   ```groovy
   pipeline {
       agent any
       stages {
           stage('Reconcile Git State') {
               steps {
                   script {
                       sh """
                       echo "Canary deployment failed in ${params.environment} for tag ${params.failed_tag}."
                       echo "Reverting values.yaml to previous stable commit..."
                       git checkout main
                       git pull origin main
                       git revert HEAD --no-edit -m 1
                       git push origin main
                       """
                   }
               }
           }
       }
   }
   ```

---

## 4. Automated Infrastructure Drift Detection & Reconciliation Jobs

### 4.1 Motivation & Current State
- **Current State**: Terraform executions are event-driven—triggered only when code commits are merged to Git. If an engineer makes manual changes directly in the AWS Management Console or via AWS CLI (out-of-band "ClickOps"), Git ceases to be the accurate single source of truth.
- **Limitation**: Silent configuration drift remains undetected until the next deployment, which can unexpectedly overwrite manual emergency hotfixes, fail due to state mismatches, or introduce security vulnerabilities (e.g., manually opened security group ports or disabled audit logging).
- **Target Goal**: Deploy automated, scheduled drift detection jobs running periodically (e.g., every 6 hours), comparing live AWS cloud state against Terraform code, dispatching Slack/email alerts, and auto-reconciling non-prod drift.

### 4.2 Implementation Steps
1. **Scheduled Drift Detection Pipeline**:
   Configure a dedicated Jenkins cron pipeline executing `terraform plan` with `-detailed-exitcode`:
   - Exit code `0`: Succeeded, diff is empty (no drift).
   - Exit code `1`: Execution error encountered.
   - Exit code `2`: Succeeded, diff present (configuration drift detected).

   ```groovy
   pipeline {
       agent any
       triggers {
           cron('H H/6 * * *') // Runs every 6 hours
       }
       stages {
           stage('Detect Cloud Drift') {
               steps {
                   dir('infra') {
                       script {
                           sh 'terraform init'
                           def exitCode = sh(
                               script: 'terraform plan -detailed-exitcode -no-color > /tmp/drift_plan.log',
                               returnStatus: true
                           )
                           if (exitCode == 2) {
                               currentBuild.result = 'UNSTABLE'
                               env.DRIFT_DETECTED = 'true'
                           } else if (exitCode != 0) {
                               error "Terraform plan failed with system error: ${exitCode}"
                           }
                       }
                   }
               }
           }
       }
   }
   ```
2. **Actionable Alerting & Drift Reporting**:
   When exit code 2 is returned, dispatch an automated notification with the parsed resource diff:
   ```groovy
   post {
       unstable {
           script {
               sh '''
               echo "Parsing drifted resources..."
               grep -E "^  # [a-zA-Z0-9_\\.]+" /tmp/drift_plan.log > /tmp/drifted_resources.txt
               '''
               slackSend(
                   channel: '#infra-drift-alerts',
                   color: 'warning',
                   message: """
                   :warning: *Infrastructure Drift Detected!*
                   Live AWS resources have drifted from Git repository baseline.
                   *Drifted Resources:*
                   ${readFile('/tmp/drifted_resources.txt')}
                   """
               )
           }
       }
   }
   ```
3. **Automated Reconciliation Strategy**:
   - **Non-Production (`dev`, `test`)**: Automatically execute `terraform apply -auto-approve` to overwrite uncommitted manual edits and strictly re-enforce Git as truth.
   - **Production (`prod`)**: Automatically open a high-priority GitHub Issue containing the plan diff, preventing unreviewed automated overwrites while alerting the platform team immediately.

---

## 5. Web Application Firewall (AWS WAF) & Zero-Trust NetworkPolicies

### 5.1 Motivation & Current State
- **Current State**: The Application Load Balancer accepts all inbound HTTP/HTTPS traffic. Subnets are isolated, but there is no inspection of HTTP payloads for malicious patterns, and pods can freely communicate across namespaces.
- **Limitation**: Vulnerable to OWASP Top 10 web exploits (SQL injection, XSS) and layer-7 DDoS floods. Compromised pods in `dev` could theoretically probe endpoints in `prod`.
- **Target Goal**: Deploy AWS WAF on the public ALB and enforce strict Kubernetes `NetworkPolicy` rules between namespaces.

### 5.2 Implementation Steps
1. **Provision AWS WAF WebACL**:
   Create an AWS WAF WebACL in Terraform with AWS Managed Rule Groups:
   - `AWSManagedRulesCommonRuleSet` (OWASP Top 10 protection).
   - `AWSManagedRulesSQLiRuleSet` (SQL injection mitigation).
   - Rate-limiting rule: Blocks any client IP exceeding 1,000 requests per 5 minutes.
2. **Attach WAF to Ingress**:
   Add the WAF WebACL annotation to `helm/petclinic/templates/ingress.yaml`:
   ```yaml
   alb.ingress.kubernetes.io/wafv2-acl-arn: "arn:aws:wafv2:us-east-1:069089526123:regional/webacl/petclinic-waf/..."
   ```
3. **Enforce Kubernetes Zero-Trust NetworkPolicies**:
   Deny all cross-namespace ingress into production namespaces:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-cross-namespace
     namespace: petclinic-prod
   spec:
     podSelector: {}
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 kubernetes.io/metadata.name: petclinic-prod
   ```

---

## 6. Ephemeral Sandbox Infrastructure Provisioning (`terraform apply` Validation)

### 6.1 Motivation & Current State
- **Current State**: CI validates Terraform using static linting (`terraform fmt`, `tflint`, `tfsec`) and speculative planning (`terraform plan`). Real changes are applied only after merging to `main`.
- **Limitation**: `terraform plan` cannot catch runtime AWS API failures such as IAM eventual consistency propagation race conditions, VPC route table quota limits, subnet IP exhaustion, or service initialization timeouts.
- **Target Goal**: Provision an isolated ephemeral Sandbox environment on PRs affecting `infra/` using dedicated state isolation (`terraform apply`), run live health assertions, and guarantee teardown (`terraform destroy`) upon PR close.

### 6.2 Implementation Steps
1. **Isolated S3 State Backend & Dynamic Key**:
   Configure a dynamic state key for sandbox PR runs to prevent state locks or overwrites against persistent environments:
   ```bash
   terraform init \
     -backend-config="bucket=petclinic-app-tfstate-069089526123-us-east-1-an" \
     -backend-config="key=sandboxes/pr-${PR_NUMBER}/terraform.tfstate" \
     -backend-config="region=us-east-1"
   ```
2. **Automated Sandbox Apply Pipeline**:
   In the PR pipeline, execute `apply` with parameter overrides for cost reduction (e.g., single-AZ NAT gateway, minimal nodes):
   ```bash
   terraform apply -auto-approve \
     -var="cluster_name=petclinic-sbx-pr-${PR_NUMBER}" \
     -var="single_nat_gateway=true" \
     -var="enable_karpenter=false"
   ```
3. **Automated Teardown Guarantee**:
   Run integration health assertions against the provisioned resources, followed by an unconditional teardown in Jenkins `post`:
   ```groovy
   post {
       always {
           script {
               sh '''
               echo "Tearing down sandbox infrastructure for PR-${PR_NUMBER}..."
               terraform destroy -auto-approve \
                 -var="cluster_name=petclinic-sbx-pr-${PR_NUMBER}" \
                 -var="single_nat_gateway=true"
               '''
           }
       }
   }
   ```

---

## 7. Ephemeral Preview Environments for Pull Requests (Argo CD ApplicationSet)

### 7.1 Motivation & Current State
- **Current State**: Developers merge feature branches into `main`, which automatically deploys to a shared `petclinic-dev` namespace.
- **Limitation**: Multiple developers working on concurrent features overwrite each other in the shared `dev` environment, making isolated testing impossible before merging.
- **Target Goal**: Dynamically spin up a lightweight, isolated environment for every open Pull Request (`petclinic-pr-123`) and automatically tear it down when the PR is merged or closed.

### 7.2 Implementation Steps
1. **Configure GitHub SCM Generator in Argo CD**:
   Deploy an `ApplicationSet` in the `argocd` namespace that watches the GitHub repository for open pull requests:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: ApplicationSet
   metadata:
     name: petclinic-pr-environments
     namespace: argocd
   spec:
     generators:
       - pullRequest:
           github:
             owner: Abdelhamid108
             repo: AtosGraduationProject
             tokenRef:
               secretName: github-token
               key: token
     template:
       metadata:
         name: 'petclinic-pr-{{number}}'
       spec:
         project: workloads-project
         source:
           repoURL: 'https://github.com/Abdelhamid108/AtosGraduationProject.git'
           targetRevision: '{{head_sha}}'
           path: helm/petclinic
           helm:
             valuesObject:
               ingress:
                 hosts:
                   - host: 'pr-{{number}}.petclinic.internal'
         destination:
           server: https://kubernetes.default.svc
           namespace: 'petclinic-pr-{{number}}'
         syncPolicy:
           automated:
             prune: true
             selfHeal: true
           syncOptions:
             - CreateNamespace=true
   ```
2. **Automated Lifecycle Hooks**:
   - The ApplicationSet controller creates namespace `petclinic-pr-<PR_NUMBER>` when a PR is opened.
   - When the PR is closed in GitHub, Argo CD prunes the application and deletes the namespace automatically.
3. **Database Configuration**:
   - Ephemeral preview environments use the in-memory `h2` database profile to avoid provisioning additional persistent EBS volumes or cloud databases.

---

## 8. Ephemeral Jenkins Build Agents (Kubernetes / AWS Fargate)

### 8.1 Motivation & Current State
- **Current State**: The Jenkins pipeline runs builds directly on a static Jenkins master/worker node (`agent { label 'master' }`).
- **Limitation**: Long-running builds queue behind each other. The static VM runs 24/7, incurring compute costs even when no builds are active.
- **Target Goal**: Launch dynamic, short-lived container pods inside Kubernetes (or AWS Fargate) for each pipeline build. The pod is created when a job starts and destroyed immediately after completion.

### 8.2 Implementation Steps
1. **Install Kubernetes Plugin in Jenkins**:
   - Configure the Kubernetes Cloud provider in Jenkins pointing to the in-cluster Kubernetes API (`https://kubernetes.default.svc`).
2. **Define PodTemplates**:
   Create dedicated containers for each task:
   - `maven` container: Runs Java compilation and unit tests.
   - `sonar` container: Runs SonarQube scanner.
   - `kaniko` container: Builds and pushes Docker images to AWS ECR without requiring Docker-in-Docker (`dind`) or root privileges.
3. **Update JTE Pipeline Templates**:
   Update `pipelines_templates/AtosGradProj/app_ci/Jenkinsfile`:
   ```groovy
   agent {
       kubernetes {
           yaml '''
           apiVersion: v1
           kind: Pod
           spec:
             containers:
             - name: maven
               image: maven:3.9.6-eclipse-temurin-17-alpine
               command: ['sleep']
               args: ['99d']
             - name: kaniko
               image: gcr.io/kaniko-project/executor:debug
               command: ['sleep']
               args: ['99d']
           '''
       }
   }
   ```

---

## 9. Automated FinOps & Cloud Cost Guardrails (Infracost on Pull Requests)

### 9.1 Motivation & Current State
- **Current State**: Infrastructure changes in `infra/` execute `terraform plan` during CI, but financial impacts are evaluated through manual estimation.
- **Limitation**: Engineers can introduce expensive architectural changes (e.g., provisioning multi-AZ NAT Gateways at ~$32/month each, over-allocating EBS GP3 IOPS, or scaling node pools to high-cost EC2 instances) without visibility into monthly cost deltas prior to merge.
- **Target Goal**: Integrate **Infracost** into the GitHub Pull Request workflow to automatically calculate monthly infrastructure cost deltas against `main`, post an itemized Markdown breakdown comment directly to the PR, and block merges if cost increases exceed a policy threshold (e.g., >$100/month).

### 9.2 Implementation Steps
1. **Configure Infracost Baseline Comparison in CI**:
   Generate baseline costs from `main` and diff against the active PR branch:
   ```bash
   # Generate baseline cost from the main branch
   git checkout origin/main
   infracost breakdown --path=infra \
     --format=json \
     --out-file=/tmp/infracost-base.json

   # Generate diff from active PR branch
   git checkout -
   infracost diff --path=infra \
     --compare-to=/tmp/infracost-base.json \
     --format=json \
     --out-file=/tmp/infracost-diff.json
   ```
2. **Automated GitHub PR Commenting**:
   Post the cost diff breakdown directly to the PR discussion:
   ```bash
   infracost comment github \
     --path=/tmp/infracost-diff.json \
     --repo=Abdelhamid108/AtosGraduationProject \
     --pull-request=${PR_NUMBER} \
     --github-token=${GITHUB_TOKEN} \
     --behavior=update
   ```
3. **FinOps Policy Guardrail (Threshold Enforcement)**:
   Add a gate in the pipeline checking the projected monthly delta:
   ```groovy
   stage('FinOps Guardrail') {
       steps {
           script {
               def diffJson = readJSON file: '/tmp/infracost-diff.json'
               def monthlyDiff = diffJson.diffTotalMonthlyCost.toFloat()
               if (monthlyDiff > 100.0) {
                   error "Monthly infrastructure cost increase (\$${monthlyDiff}) exceeds the \$100 policy threshold. Tech lead approval required."
               }
           }
       }
   }
   ```

---

## 10. Prometheus Long-Term Storage (AWS AMP / Thanos Remote-Write)

### 10.1 Motivation & Current State
- **Current State**: Prometheus stores metric data on a local EBS volume in the cluster with a 15-day retention limit.
- **Limitation**: Metrics older than 15 days are permanently deleted. A crashed EBS volume risks metric data loss.
- **Target Goal**: Stream metrics to **Amazon Managed Service for Prometheus (AMP)** for durable, long-term metric storage.

### 10.2 Implementation Steps
1. **Provision AWS AMP Workspace**:
   ```bash
   aws amp create-workspace --alias petclinic-metrics
   ```
2. **Enable Remote-Write in Prometheus Values**:
   In `gitops/platform/monitoring/values-prometheus.yaml`:
   ```yaml
   prometheus:
     prometheusSpec:
       remoteWrite:
         - url: https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-XXXX/api/v1/remote_write
           sigv4:
             region: us-east-1
           queueConfig:
             maxSamplesPerSend: 1000
             maxShards: 200
   ```
3. **Configure IAM Pod Identity**:
   Grant the Prometheus service account IAM role permission `aps:RemoteWriteExec`.

---

## 11. End-to-End Automated Testing Scenarios (k6 Load & Chaos Mesh)

### 11.1 Motivation & Current State
- **Current State**: Automated testing consists of Maven unit tests and SonarQube static analysis.
- **Limitation**: Does not stress-test autoscaling, does not verify canary rollback behavior under live failure, and does not validate pod recovery during node failures.
- **Target Goal**: Implement automated integration tests, synthetic load generation, and chaos testing.

### 11.2 Implementation Steps
1. **Load Testing with k6**:
   Create a dedicated k6 test script simulating user traffic:
   ```javascript
   // tests/load/k6-scenario.js
   import http from 'k6/http';
   import { check, sleep } from 'k6';

   export const options = {
     stages: [
       { duration: '2m', target: 50 },  // Ramp-up to 50 users
       { duration: '5m', target: 200 }, // Stress test at 200 users (triggers HPA & Karpenter)
       { duration: '2m', target: 0 },   // Ramp-down
     ],
   };

   export default function () {
     let res = http.get('https://petclinic.internal/owners');
     check(res, { 'status is 200': (r) => r.status === 200 });
     sleep(1);
   }
   ```
2. **Chaos Testing (Pod / Node Terminations)**:
   - Deploy **Chaos Mesh** or a simple test script that randomly deletes a workload pod during an active load test to verify that the PodDisruptionBudget (`minAvailable: 1`) and graceful shutdown prevent dropped HTTP requests.

---

## 12. AWS Client VPN for Private Cluster Access

### 12.1 Motivation & Current State
- **Current State**: The EKS API endpoint is private (`endpoint_public_access = false`). Engineers must start an AWS SSM Session Manager WebSocket tunnel through the Bastion host to run `kubectl`.
- **Limitation**: High operational friction for developers debugging issues; terminal latency over SSM websockets.
- **Target Goal**: Deploy an AWS Client VPN endpoint connected to the private subnets.

### 12.2 Implementation Steps
1. **Generate Mutual TLS Certificates**:
   Generate server and client certificates using EasyRSA and import them into AWS ACM:
   ```bash
   aws acm import-certificate --certificate fileb://server.crt --private-key fileb://server.key --certificate-chain fileb://ca.crt
   ```
2. **Provision Client VPN in Terraform**:
   Add to `infra/modules/compute/vpn.tf`:
   ```hcl
   resource "aws_ec2_client_vpn_endpoint" "vpn" {
     description            = "EKS Private Access VPN"
     server_certificate_arn = aws_acm_certificate.server.arn
     client_cidr_block      = "172.16.0.0/22"

     authentication_options {
       type                       = "certificate-authentication"
       root_certificate_chain_arn = aws_acm_certificate.client.arn
     }

     connection_log_options { enabled = false }
   }

   resource "aws_ec2_client_vpn_network_association" "private" {
     count                  = length(module.vpc.private_subnets)
     client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.vpn.id
     subnet_id              = module.vpc.private_subnets[count.index]
   }
   ```
3. **Connect**:
   Engineers import the `.ovpn` profile into OpenVPN Client and connect directly to private cluster endpoints without Bastion port-forwarding.

---

## 13. Resource Rightsizing & Tuning from Real Load Data

### 13.1 Motivation & Current State
- **Current State**: Container CPU and memory requests/limits (`requests: 250m / 512Mi`, `limits: 500m / 1Gi`) are baseline estimates.
- **Limitation**: Over-provisioned requests waste EC2 capacity; under-provisioned requests risk latency spikes or premature pod evictions.
- **Target Goal**: Use empirical data gathered during load test cycles to define accurate, cost-effective resource requests and limits.

### 13.2 Implementation Steps
1. **Collect Metric Baselines During Load Tests**:
   Query Prometheus during the k6 load test:
   - CPU 95th Percentile:
     ```promql
     quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{container="petclinic"}[5m])[1h:])
     ```
   - Working Set Memory 95th Percentile:
     ```promql
     quantile_over_time(0.95, container_memory_working_set_bytes{container="petclinic"}[1h:])
     ```
2. **Tune Resource Values**:
   - Set **CPU Request** to the observed P75 utilization.
   - Set **CPU Limit** to `none` (or high ceiling) to prevent CPU throttling.
   - Set **Memory Request** to the observed P90 working set.
   - Set **Memory Limit** to $1.25 \times \text{Request}$ to provide headroom for garbage collection spikes while protecting node stability.
3. **Update Helm Values**:
   Update `helm/petclinic/values.yaml` with the measured parameters to maximize Karpenter bin-packing efficiency.
