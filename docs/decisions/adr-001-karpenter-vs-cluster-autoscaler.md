# ADR-001: Karpenter vs. Kubernetes Cluster Autoscaler

## Context
The EKS cluster needs to scale compute capacity when pod traffic spikes and shrink capacity when load drops to control AWS infrastructure costs.

## Decision
We chose **Karpenter** over the standard Kubernetes Cluster Autoscaler.

## Comparison

| Criteria | Cluster Autoscaler | Karpenter (Selected) |
| :--- | :--- | :--- |
| **AWS Integration** | Requires creating multiple AWS Auto Scaling Groups (ASGs) in Terraform. | Talks directly to AWS EC2 Fleet APIs. No ASGs needed. |
| **Instance Selection** | Limited to the specific instance type configured inside each ASG. | Dynamically chooses from all available EC2 types based on pod requirements. |
| **Provisioning Speed** | 3 to 6 minutes (waits for ASG scaling and EC2 boot). | 30 to 45 seconds (direct API calls and fast node initialization). |
| **Scale Down / Packing** | Only scales down when a node is completely empty. | Actively consolidates workloads onto fewer or smaller instances when underutilized. |
| **Spot Handling** | Requires external tools or scripts for spot termination notices. | Native integration with Amazon EventBridge and SQS to drain nodes 2 minutes before spot termination. |

## Implementation
- Terraform module: [`infra/modules/eks/karpenter.tf`](file:///home/devops/Atos/AtosGraduationProject/infra/modules/eks/karpenter.tf)
- NodePool definition: [`gitops/platform/karpenter/nodepool.yaml`](file:///home/devops/Atos/AtosGraduationProject/gitops/platform/karpenter/nodepool.yaml)

## Consequences
- Requires running the Karpenter controller inside the cluster (`karpenter` namespace).
- Requires an SQS queue and EventBridge rules to receive EC2 Spot interruption events.
