#!/usr/bin/env bash
set -euo pipefail

# One-time cluster bootstrap: installs Argo CD, then applies the single root
# Application. After this runs once, every other manifest in gitops/ is
# reconciled by Argo CD itself — never kubectl-applied by hand again.

CLUSTER_NAME="${CLUSTER_NAME:-<REPLACE_ME_CLUSTER_NAME>}"   # not provisioned yet — placeholder
AWS_REGION="${AWS_REGION:-<REPLACE_ME_REGION>}"               # not provisioned yet — placeholder
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.2}"   # pinned deliberately, not 'stable'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Configuring kubeconfig for cluster '${CLUSTER_NAME}' in '${AWS_REGION}'"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

echo "==> Creating '${ARGOCD_NAMESPACE}' namespace (idempotent)"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD ${ARGOCD_VERSION}"
kubectl apply -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for the Argo CD API server to come up"
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-server --timeout=300s

echo "==> Applying the root Application (the ONLY manual kubectl apply this project needs)"
kubectl apply -f "${SCRIPT_DIR}/root-application.yaml"

echo "==> Done. Watch reconciliation with:"
echo "    kubectl -n ${ARGOCD_NAMESPACE} get applications"
