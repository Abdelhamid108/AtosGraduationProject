# Architecture Decision Records (ADRs)

This directory records the key technical decisions made in the project. Each document explains the context, the options considered, why a specific choice was made, and the consequences.

---

## Decision Index

| ID | Title | Status | Primary Reason |
| :--- | :--- | :---: | :--- |
| [ADR-001](adr-001-karpenter-vs-cluster-autoscaler.md) | **Karpenter vs. Cluster Autoscaler** | Accepted | Sub-minute node provisioning directly via EC2 fleet APIs without Auto Scaling Groups. |
| [ADR-002](adr-002-eks-pod-identity-vs-irsa.md) | **EKS Pod Identity vs. IRSA** | Accepted | Eliminates OIDC provider setup and role trust policy mutations across cluster rebuilds. |
| [ADR-003](adr-003-argo-rollouts-canary-vs-native-rolling-update.md) | **Argo Rollouts vs. Standard Rolling Updates** | Accepted | Automated canary analysis with Prometheus error budget verification and instant rollback. |
| [ADR-004](adr-004-jenkins-jte-governance-vs-monolithic-jenkinsfiles.md) | **Jenkins JTE vs. Monolithic Jenkinsfiles** | Accepted | Reusable shared step libraries and centralized security gates across all pipelines. |
| [ADR-005](adr-005-deterministic-iam-naming-strategy.md) | **Deterministic IAM Role Naming** | Accepted | Stops AWS random hash suffixes from breaking GitOps manifests across terraform destroy/apply. |
| [ADR-006](adr-006-argocd-image-updater-vs-ci-git-writeback.md) | **Argo CD Image Updater vs. CI Deployments** | Accepted | In-cluster ECR polling and automated Git write-back without exposing cluster or Git write keys to CI. |
| [ADR-007](adr-007-trunk-based-branching-and-tag-driven-promotion.md) | **Trunk-Based Branching & Tag-Driven Promotion** | Accepted | Single source of truth on main, immutable container artifacts, and gated tag promotions (`v*-rc` -> `v*`). |
