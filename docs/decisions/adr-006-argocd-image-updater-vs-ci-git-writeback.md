# ADR-006: Argo CD Image Updater vs. CI-Driven Deployments

## Context
When the Jenkins CI pipeline builds and pushes a new container image tag to AWS ECR, the application deployment must be updated with the new image.

We evaluated how to connect container image publishing in CI to the deployment in Kubernetes while preserving GitOps principles.

## Decision
We chose **Argo CD Image Updater** running as an in-cluster controller to detect new images and write updates back to Git.

## Options Considered

1. **Direct CI Deployments (`kubectl apply` / `helm upgrade` from Jenkins)**
   - Jenkins runs `kubectl set image` or `helm upgrade` directly against the EKS cluster.
   - *Rejected*: Breaks GitOps. The Git repository is bypassed, causing drift between Git and the actual cluster state. It also requires giving the Jenkins runner cluster administrative access.

2. **CI-Driven Git Commits (Jenkins pushes to GitOps repo)**
   - Jenkins clones the GitOps repository, modifies `values.yaml`, and pushes a commit back to GitHub.
   - *Rejected*: Requires distributing Git write tokens and SSH deploy keys across CI runners. If multiple branch builds finish simultaneously, concurrent Git pushes cause merge conflicts.

3. **In-Cluster Pull Controller (Argo CD Image Updater - Selected)**
   - Argo CD Image Updater runs inside the EKS cluster.
   - It polls AWS ECR using an IAM role through EKS Pod Identity (no static AWS credentials needed).
   - When a new tag matching the configured regex (e.g. `^dev-[a-f0-9]+$`) is discovered, it writes the new tag to `gitops/workloads/<env>/values.yaml` and commits directly to Git.
   - Argo CD detects the commit and synchronizes the application.

## Comparison

| Criteria | Direct CI Deploy (`kubectl`) | CI Git Push (Jenkins) | Argo CD Image Updater (Selected) |
| :--- | :--- | :--- | :--- |
| **GitOps Compliance** | None. Cluster state drifts from Git. | Yes. Git is updated. | Yes. Git remains the single source of truth. |
| **CI Runner Credentials** | Requires full EKS cluster access. | Requires Git write tokens in Jenkins. | CI only needs permission to push to AWS ECR. |
| **AWS Authentication** | Static IAM keys or complex IRSA. | N/A (Git operations only). | Uses EKS Pod Identity (`pods.eks.amazonaws.com`). |
| **Concurrency Handling** | Overwrites running pods directly. | Susceptible to Git push race conditions. | Handled sequentially by the in-cluster controller. |

## Implementation
- Controller manifest: [`gitops/platform/image-updater/application.yaml`](file:///home/devops/Atos/AtosGraduationProject/gitops/platform/image-updater/application.yaml)
- Workload annotations: [`gitops/workloads/dev/application.yaml`](file:///home/devops/Atos/AtosGraduationProject/gitops/workloads/dev/application.yaml)
- IAM role: `atos-eks-cluster-image-updater-role` in [`infra/modules/iam/main.tf`](file:///home/devops/Atos/AtosGraduationProject/infra/modules/iam/main.tf)

## Consequences & Known Limitations
- Requires running the `argocd-image-updater` pod in the `argocd` namespace.
- Introduces a polling delay (default 2 minutes) between image push to ECR and the Git commit.

### Unhandled Problem: Git and Cluster Divergence on Canary Abort
This is an **unhandled problem** in our current setup:
1. Image Updater detects a new image and writes `image.tag: v1.2.0` directly to `values.yaml` in Git.
2. Argo CD syncs the cluster, and Argo Rollouts starts a canary rollout.
3. Prometheus analysis fails, and Argo Rollouts **aborts** the release, safely reverting cluster traffic to the old version (`v1.1.0`).
4. **The Unhandled Flaw**: The cluster is running `v1.1.0`, but Git still says `v1.2.0`.
5. **No automated rollback exists in Git**: There is no script or controller in this repository to revert the Git commit.
6. **Required Action**: An engineer must manually revert the Git commit or push a hotfix. Until someone does, Git is out of sync with what is actually running.
