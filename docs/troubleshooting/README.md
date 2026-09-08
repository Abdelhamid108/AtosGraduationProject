# Operational Runbooks & Troubleshooting Guide

This directory contains operational runbooks and architectural diagnostic guides for the Spring PetClinic platform.

---

## Runbook Directory & Incident Lookup

| ID | Issue / Domain | Symptoms & Focus | Document |
| :---: | :--- | :--- | :--- |
| **01** | **Control Plane & Bastion Access** | Cannot run `kubectl` from outside the VPC; SSM TargetNotConnected errors. | [01-private-cluster-control-plane-and-bastion-architecture.md](01-private-cluster-control-plane-and-bastion-architecture.md) |
| **02** | **EKS Pod Identity & Storage** | Pod cannot authenticate to AWS services; EBS volumes failing to mount. | [02-eks-pod-identity-and-addon-lifecycle-architecture.md](02-eks-pod-identity-and-addon-lifecycle-architecture.md) |
| **03** | **Kubernetes RBAC Access Entries** | `Unauthorized` or `forbidden` errors when executing `kubectl` commands. | [03-kubernetes-rbac-and-declarative-access-entries-architecture.md](03-kubernetes-rbac-and-declarative-access-entries-architecture.md) |
| **04** | **Subnet Topology & ALB Discovery** | `couldn't auto-discover subnets` when creating Application Load Balancers. | [04-multi-az-subnet-topology-and-load-balancer-discovery.md](04-multi-az-subnet-topology-and-load-balancer-discovery.md) |
| **05** | **Temporary Credentials & STS** | `ExpiredToken` or `InvalidClientTokenId` during Terraform CI runs. | [05-temporary-credentials-and-dynamic-role-delegation.md](05-temporary-credentials-and-dynamic-role-delegation.md) |
| **06** | **Karpenter Node Provisioning** | Unschedulable pods not triggering node launches; `iam:PassRole` access denied. | [06-karpenter-autoscaling-and-spot-interruption-architecture.md](06-karpenter-autoscaling-and-spot-interruption-architecture.md) |
| **07** | **ACM Certificates & HTTPS Redirect** | `CertificateNotFound` errors; traffic connecting on port 80 not redirecting to 443. | [07-acm-certificates-and-https-redirection.md](07-acm-certificates-and-https-redirection.md) |
| **08** | **PrometheusRule Webhook Denials** | `admission webhook denied the request: Rules are not valid` on Helm/Argo apply. | [08-prometheus-rule-validation-and-webhook-denials.md](08-prometheus-rule-validation-and-webhook-denials.md) |
| **09** | **Argo Rollouts Canary Degradation** | Rollouts stuck at 20%/40%; automated analysis failures; emergency rollbacks. | [09-argo-rollouts-canary-degradation-and-rollback.md](09-argo-rollouts-canary-degradation-and-rollback.md) |
