# Future Roadmap, Technical Debt & Unimplemented Improvements

This document outlines the architectural enhancements, security hardening, testing pipelines, and operational improvements that were planned but could not be fully implemented in the current release. 

Each section provides the technical motivation, the current state, and step-by-step implementation procedures for future execution.

---

## 1. Ephemeral Preview Environments for Pull Requests (Argo CD ApplicationSet)

### 1.1 Motivation & Current State
- **Current State**: Developers merge feature branches into `main`, which automatically deploys to a shared `petclinic-dev` namespace.
- **Limitation**: Multiple developers working on concurrent features overwrite each other in the shared `dev` environment, making isolated testing impossible before merging.
- **Target Goal**: Dynamically spin up a lightweight, isolated environment for every open Pull Request (`petclinic-pr-123`) and automatically tear it down when the PR is merged or closed.

### 1.2 Implementation Steps
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
   - When the PR is merged or closed in GitHub, the SCM generator drops the PR from the list, triggering Argo CD to prune the application and delete the namespace automatically.
3. **Database Configuration**:
   - Ephemeral environments use the in-memory `h2` database profile to avoid provisioning additional persistent EBS volumes or cloud databases.

---

## 2. Prod vs. Non-Prod Cluster Isolation

### 2.1 Motivation & Current State
- **Current State**: All environments (`dev`, `test`, `prod`) run inside a single Amazon EKS cluster (`atos-eks-cluster`), separated only by Kubernetes namespaces.
- **Limitation**: A misconfigured workload in `dev` (such as a memory leak or CPU spike) can saturate worker nodes and impact production workloads if resource quotas or Karpenter limits are misconfigured.
- **Target Goal**: Physical separation into two distinct clusters:
  - `non-prod-eks-cluster`: Hosts `dev`, `test`, and ephemeral PR environments.
  - `prod-eks-cluster`: Strictly hosts `prod` with dedicated node groups and tighter security boundaries.

### 2.2 Implementation Steps
1. **Split Terraform Configurations**:
   Create two separate environment roots in `infra/`:
   ```text
   infra/
   ├── modules/            # Shared reusable modules (vpc, eks, iam, compute)
   └── environments/
       ├── non-prod/       # Terraform root for non-prod VPC & EKS
       └── prod/           # Terraform root for production VPC & EKS
   ```
2. **VPC Separation & Peering**:
   - Deploy non-prod in `10.1.0.0/16` and prod in `10.2.0.0/16`.
   - Prevent any network routing between the two VPCs except through controlled AWS Transit Gateway or VPC Endpoints.
3. **IAM Boundary Isolation**:
   - Non-prod IAM roles have zero read or write permissions to production AWS Secrets Manager keys, S3 buckets, or RDS databases.

---

## 3. Ephemeral Jenkins Build Agents (Kubernetes / AWS Fargate)

### 3.1 Motivation & Current State
- **Current State**: The Jenkins pipeline runs builds directly on a static Jenkins master/worker node (`agent { label 'master' }`).
- **Limitation**: Long-running builds queue behind each other. The static VM runs 24/7, incurring compute costs even when no builds are active.
- **Target Goal**: Launch dynamic, short-lived container pods inside Kubernetes (or AWS Fargate) for each pipeline build. The pod is created when a job starts and destroyed immediately after completion.

### 3.2 Implementation Steps
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

## 4. AWS Client VPN for Private Cluster Access

### 4.1 Motivation & Current State
- **Current State**: The EKS API endpoint is private (`endpoint_public_access = false`). Engineers must start an AWS SSM Session Manager WebSocket tunnel through the Bastion host to run `kubectl`.
- **Limitation**: High operational friction for developers debugging issues; terminal latency over SSM websockets.
- **Target Goal**: Deploy an AWS Client VPN endpoint connected to the private subnets.

### 4.2 Implementation Steps
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

## 5. End-to-End Automated Testing Scenarios (Load & Chaos)

### 5.1 Motivation & Current State
- **Current State**: Automated testing consists of Maven unit tests and SonarQube static analysis.
- **Limitation**: Does not stress-test autoscaling, does not verify canary rollback behavior under live failure, and does not validate pod recovery during node failures.
- **Target Goal**: Implement automated integration tests, synthetic load generation, and chaos testing.

### 5.2 Implementation Steps
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

## 6. Web Application Firewall (AWS WAF) & Network Policies

### 6.1 Motivation & Current State
- **Current State**: The Application Load Balancer accepts all inbound HTTP/HTTPS traffic. Subnets are isolated, but there is no inspection of HTTP payloads for malicious patterns, and pods can freely communicate across namespaces.
- **Target Goal**: Deploy AWS WAF on the ALB and enforce Kubernetes `NetworkPolicy` rules between namespaces.

### 6.2 Implementation Steps
1. **Provision AWS WAF WebACL**:
   Create an AWS WAF WebACL in Terraform with AWS Managed Rule Groups:
   - `AWSManagedRulesCommonRuleSet` (protects against OWASP Top 10 vulnerabilities).
   - `AWSManagedRulesSQLiRuleSet` (blocks SQL injection attempts).
   - Rate-limiting rule: Blocks IPs exceeding 1,000 requests per 5 minutes.
2. **Attach WAF to Ingress**:
   Add the WAF annotation to `helm/petclinic/templates/ingress.yaml`:
   ```yaml
   alb.ingress.kubernetes.io/wafv2-acl-arn: "arn:aws:wafv2:us-east-1:069089526123:regional/webacl/petclinic-waf/..."
   ```
3. **Enforce Kubernetes NetworkPolicies**:
   Block cross-namespace communication so compromised pods in `dev` cannot access the `prod` database:
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

## 7. Prometheus Long-Term Storage (AWS AMP / Thanos Remote-Write)

### 7.1 Motivation & Current State
- **Current State**: Prometheus stores metric data on a local EBS volume in the cluster with a 15-day retention limit.
- **Limitation**: Metrics older than 15 days are permanently deleted. A crashed EBS volume risks metric data loss.
- **Target Goal**: Stream metrics to **Amazon Managed Service for Prometheus (AMP)** for durable, long-term metric storage.

### 7.2 Implementation Steps
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

## 8. Pipeline Synchronization & Automated Rollout Verification

### 8.1 Motivation & Current State
- **Current State**: The Jenkins CI pipeline pushes image tags to ECR and immediately terminates. It has no visibility into whether the Argo Rollouts canary deployment succeeded or aborted in the cluster.
- **Limitation**: Jenkins reports "SUCCESS" even if the application failed canary verification and was aborted by Argo Rollouts.
- **Target Goal**: Have the Jenkins pipeline wait for rollout verification, check the analysis outcome, and automatically trigger a Git revert if the canary fails.

### 8.2 Implementation Steps
1. **Add Verification Stage to Jenkinsfile**:
   In `pipelines_templates/AtosGradProj/app_ci/Jenkinsfile`:
   ```groovy
   stage('Verify Rollout') {
       steps {
           script {
               sh '''
               echo "Waiting for Argo Rollouts canary verification in TEST..."
               kubectl argo rollouts status rollout petclinic -n petclinic-test --timeout=10m
               '''
           }
       }
   }
   ```
2. **Automated Git Revert on Failure**:
   Add a failure hook in Jenkins to revert the commit if the rollout fails:
   ```groovy
   post {
       failure {
           script {
               sh '''
               echo "Canary failed. Reverting image tag in Git to previous stable version..."
               git revert HEAD --no-edit
               git push origin main
               '''
           }
       }
   }
   ```

---

## 9. Resource Rightsizing & Tuning from Real Load Data

### 9.1 Motivation & Current State
- **Current State**: Container CPU and memory requests/limits (`requests: 250m / 512Mi`, `limits: 500m / 1Gi`) are baseline estimates.
- **Limitation**: Over-provisioned requests waste EC2 capacity; under-provisioned requests risk latency spikes or premature pod evictions.
- **Target Goal**: Use empirical data gathered during load test cycles to define accurate, cost-effective resource requests and limits.

### 9.2 Implementation Steps
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

---

## 10. Automated FinOps & Cloud Cost Guardrails (Infracost on Pull Requests)

### 10.1 Motivation & Current State
- **Current State**: Infrastructure changes in `infra/` execute `terraform plan` during CI, but financial impacts are evaluated through manual estimation.
- **Limitation**: Engineers can introduce expensive architectural changes (e.g., provisioning multi-AZ NAT Gateways at ~$32/month each plus data transfer, over-allocating EBS GP3 provisioned IOPS/throughput, or modifying node pool specs to high-cost EC2 instances) without visibility into the monthly cost delta prior to merge.
- **Target Goal**: Integrate **Infracost** into the GitHub Pull Request workflow to automatically calculate monthly infrastructure cost deltas against the baseline state on `main`, post an itemized Markdown breakdown comment directly to the PR, and block merges if cost increases exceed an organizational threshold (e.g., >$100/month without lead approval).

### 10.2 Implementation Steps
1. **Configure Infracost Baseline Comparison in CI**:
   Store the Infracost API key in Jenkins credentials (`INFRACOST_API_KEY`). In the PR pipeline, generate the baseline cost from `main` and the delta from the active PR branch:
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
   Post the cost diff breakdown directly to the PR discussion using the Infracost CLI:
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

## 11. Ephemeral Sandbox Infrastructure Provisioning (`terraform apply` Validation)

### 11.1 Motivation & Current State
- **Current State**: CI validates Terraform using static linting (`terraform fmt`, `tflint`, `tfsec`) and speculative planning (`terraform plan`). The code is only applied after merge to the persistent cluster infrastructure.
- **Limitation**: `terraform plan` only queries cloud provider APIs to preview planned changes and validate syntax. It cannot detect runtime failures that only occur during real API creation, such as IAM propagation race conditions, VPC route table limit exhaustion, AWS service quota denials, CIDR overlap collisions, or sub-component initialization timeouts.
- **Target Goal**: Automatically provision an ephemeral Sandbox environment on Pull Requests affecting `infra/` using dedicated state isolation (`terraform apply`), run automated health assertions against the provisioned cloud resources, and guarantee teardown (`terraform destroy`) upon completion.

### 11.2 Implementation Steps
1. **Isolated S3 State Backend & Dynamic Key**:
   Configure a dynamic state key for sandbox PR runs to prevent state locks or overwrites against persistent environments:
   ```bash
   terraform init \
     -backend-config="bucket=petclinic-app-tfstate-069089526123-us-east-1-an" \
     -backend-config="key=sandboxes/pr-${PR_NUMBER}/terraform.tfstate" \
     -backend-config="region=us-east-1"
   ```
2. **Automated Sandbox Apply Pipeline**:
   In the PR pipeline, execute `apply` with parameter overrides for sandbox resource limits (e.g., single-AZ NAT gateway, reduced node counts) to minimize cloud spend during validation:
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

## 12. Automated Infrastructure Drift Detection & Reconciliation Jobs

### 12.1 Motivation & Current State
- **Current State**: Terraform executions are event-driven—triggered only when code commits are merged to Git. If an engineer makes manual changes directly in the AWS Management Console or via AWS CLI (out-of-band "ClickOps"), Git ceases to be the accurate single source of truth.
- **Limitation**: Silent configuration drift remains undetected until the next deployment, which can unexpectedly overwrite manual emergency hotfixes, fail due to state mismatches, or introduce security and compliance vulnerabilities (e.g., manually opened security group ports or disabled logging).
- **Target Goal**: Deploy automated, scheduled drift detection jobs that run periodically (e.g., every 6 hours or nightly), compare live cloud state against the Terraform code in Git, alert engineers on detected drift, and optionally auto-reconcile state back to the Git baseline.

### 12.2 Implementation Steps
1. **Scheduled Drift Detection Pipeline**:
   Configure a dedicated Jenkins cron pipeline executing `terraform plan` with `-detailed-exitcode`:
   - Exit code `0`: Succeeded, diff is empty (no drift).
   - Exit code `1`: Execution error encountered.
   - Exit code `2`: Succeeded, changes present (configuration drift detected).

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
                           // -detailed-exitcode returns 2 when diff exists
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
   When exit code 2 is returned, dispatch an automated notification with the parsed resource diff to Slack or incident management:
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
                   Live AWS resources have drifted from the Git repository.
                   *Drifted Resources:*
                   ${readFile('/tmp/drifted_resources.txt')}
                   Review the attached plan log to reconcile.
                   """
               )
           }
       }
   }
   ```
3. **Automated Reconciliation Strategy**:
   - **Non-Production (`dev`, `test`)**: Automatically execute `terraform apply -auto-approve` to overwrite uncommitted manual edits and strictly enforce Git as the single source of truth.
   - **Production (`prod`)**: Automatically open a GitHub Issue or PagerDuty incident containing the drift diff, preventing unreviewed automated overwrites while alerting the platform team immediately.



