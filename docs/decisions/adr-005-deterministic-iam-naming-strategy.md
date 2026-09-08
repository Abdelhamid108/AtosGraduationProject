# ADR-005: Deterministic IAM Role Naming for GitOps Compatibility

## Context
By default, the official Terraform AWS EKS Karpenter submodule (`terraform-aws-modules/eks/aws//modules/karpenter`) sets `node_iam_role_use_name_prefix = true`. 

When name prefixing is enabled, AWS IAM automatically appends a random 26-character alphanumeric suffix to the role name (for example, `Karpenter-atos-eks-cluster-a0a38be52809736011518b1edc`). Every time the infrastructure is destroyed and recreated via `terraform destroy` and `terraform apply`, AWS generates a completely new random suffix.

Because the Kubernetes Karpenter `EC2NodeClass` requires the exact IAM role name in its `spec.role` field, this random suffix required engineers to manually copy-paste the new role name into `gitops/platform/karpenter/nodepool.yaml` after every deployment.

## Decision
We disabled name prefixing and enforced **deterministic, fixed IAM role naming** in Terraform:

```hcl
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # Deterministic naming: Prevents random hash generation across redeployments
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "Karpenter-${var.cluster_name}"
  ...
}
```

## Comparison

| Criteria | Random Prefix Naming (Default) | Deterministic Fixed Naming (Selected) |
| :--- | :--- | :--- |
| **Role Name Pattern** | `Karpenter-<cluster>-<RANDOM_HASH>` | `Karpenter-<cluster>` |
| **Deploy / Destroy Behavior** | A new random string is generated on every apply. | The role name is always identical across every destroy and apply. |
| **GitOps Integration** | Anti-pattern. Engineers must manually edit `nodepool.yaml` in Git after every Terraform run. | Fully automated. `nodepool.yaml` hardcodes `role: "Karpenter-atos-eks-cluster"` permanently. |
| **IAM Policy Alignment** | Controller `iam:PassRole` permissions frequently drift from the Kubernetes manifest. | Controller `iam:PassRole` permissions and the `EC2NodeClass` match on day 1. |

## Implementation
- Terraform Module: [`infra/modules/eks/karpenter.tf`](file:///home/devops/Atos/AtosGraduationProject/infra/modules/eks/karpenter.tf)
- Kubernetes NodeClass: [`gitops/platform/karpenter/nodepool.yaml`](file:///home/devops/Atos/AtosGraduationProject/gitops/platform/karpenter/nodepool.yaml)

## Consequences
- Role names must not collide with other clusters in the same AWS account (avoided by including `${var.cluster_name}` in the role name).
