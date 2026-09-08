# ADR-003: Argo Rollouts Canary vs. Standard Kubernetes Rolling Updates

## Context
When rolling out a new version of the Spring PetClinic application, we need to ensure that bugs or regressions do not cause a full service outage for end users.

## Decision
We chose **Argo Rollouts with Canary Analysis** for `test` and `prod` environments, while keeping standard `Deployment` objects for `dev`.

## Comparison

| Criteria | Standard Kubernetes Deployment | Argo Rollouts (Selected) |
| :--- | :--- | :--- |
| **Traffic Splitting** | Replaces pods pod-by-pod. Cannot control exact traffic percentage (e.g. exactly 20% of requests). | Integrates with the load balancer / service mesh to route exact traffic percentages (20%, 40%, etc.). |
| **Verification** | Relies solely on Kubernetes Readiness Probes. If the probe passes, pods are considered healthy. | Runs background metric analysis (PromQL queries) against Prometheus while real traffic is flowing. |
| **Automatic Rollback** | None. If a new version passes readiness checks but returns HTTP 500 errors to users, it replaces 100% of pods. | If the error rate exceeds 1% during analysis, it immediately aborts and shifts 100% of traffic back to stable pods. |
| **Complexity** | Simple native Kubernetes resource. | Requires the Argo Rollouts controller and Custom Resource Definitions (CRDs). |

## Implementation
- Workload template: [`helm/petclinic/templates/rollout.yaml`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/templates/rollout.yaml)
- Prometheus query: [`helm/petclinic/templates/analysis-template.yaml`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/templates/analysis-template.yaml)
- Toggled via `rollout.enabled = true` in environment values files.

## Consequences
- Requires the `argo-rollouts` controller installed in the `argo-rollouts` namespace.
- Developers must inspect Rollout CRDs (`kubectl argo rollouts get rollout ...`) rather than standard Deployments during canary releases.
