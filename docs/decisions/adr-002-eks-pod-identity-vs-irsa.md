# ADR-002: EKS Pod Identity vs. IAM Roles for Service Accounts (IRSA)

## Context
Kubernetes workloads (such as the AWS Load Balancer Controller, External Secrets Operator, and Image Updater) need to authenticate to AWS APIs without hardcoding long-lived AWS IAM access keys in Kubernetes secrets.

## Decision
We chose **EKS Pod Identity** instead of the older IAM Roles for Service Accounts (IRSA) mechanism.

## Comparison

| Criteria | IAM Roles for Service Accounts (IRSA) | EKS Pod Identity (Selected) |
| :--- | :--- | :--- |
| **Trust Policy** | Requires the cluster OIDC provider URL in each role trust policy. | Uses a static trust policy: `pods.eks.amazonaws.com`. |
| **Cluster Rebuilds** | When a cluster is destroyed and recreated, the OIDC URL changes. Every IAM role trust policy breaks and must be updated. | Roles remain valid across cluster recreations. Only the association needs to be reapplied. |
| **Configuration** | Configured via annotations on Kubernetes `ServiceAccount` manifests. | Configured via standard AWS EKS API calls (`aws_eks_pod_identity_association`). |
| **Agent Requirement** | No cluster agent required (uses Kubernetes projected service account tokens). | Requires the `eks-pod-identity-agent` EKS add-on running as a DaemonSet. |

## Implementation
- EKS Add-on & Associations: [`infra/modules/eks/pod_identity.tf`](file:///home/devops/Atos/AtosGraduationProject/infra/modules/eks/pod_identity.tf)
- IAM Roles: [`infra/modules/iam/main.tf`](file:///home/devops/Atos/AtosGraduationProject/infra/modules/iam/main.tf)

## Trust Policy Comparison
### Legacy IRSA Trust Policy (Cluster-specific):
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::069089526123:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/42DF072577988159B30CCE5976"
  },
  "Action": "sts:AssumeRoleWithWebIdentity"
}
```

### Modern Pod Identity Trust Policy (Reusable):
```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": [
    "sts:AssumeRole",
    "sts:TagSession"
  ]
}
```

## Consequences
- Requires the `eks-pod-identity-agent` addon installed on the EKS cluster.
- Pods must use an AWS SDK version released after November 2023 that supports the container credentials endpoint.
