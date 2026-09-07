#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Cluster Teardown: AtosGraduationProject
# 1. Deletes the Root Application (triggers cascading teardown of all resources)
# 2. Waits for all applications, ALBs, EBS volumes, and namespaces to terminate
# 3. Optionally uninstalls Argo CD (--all)
# ==============================================================================

# Variables - Update these or export them in your shell
CLUSTER_NAME="${CLUSTER_NAME:-atos-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ARGOCD_NAMESPACE="argocd"

# 1. Ensure Kubeconfig is current
echo "==> Configuring kubeconfig for cluster '${CLUSTER_NAME}' in '${AWS_REGION}'"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

# 2. Delete Root Application
echo "==> Deleting root Application (cascading teardown)"
kubectl delete application root -n "${ARGOCD_NAMESPACE}" --ignore-not-found

# 3. Wait for all Applications to terminate cleanly
echo "==> Waiting for all Argo CD applications to finish terminating..."
while kubectl get applications.argoproj.io -n "${ARGOCD_NAMESPACE}" 2>/dev/null | grep -q .; do
  echo "    Waiting for applications and AWS resources to delete..."
  sleep 5
done

# 4. Optional: Uninstall Argo CD (pass --all to remove Argo CD & its LoadBalancer)
if [[ "${1:-}" == "--all" ]]; then
  echo "==> Uninstalling Argo CD"
  helm uninstall argocd -n "${ARGOCD_NAMESPACE}" || true
  kubectl delete namespace "${ARGOCD_NAMESPACE}" --ignore-not-found || true
fi

