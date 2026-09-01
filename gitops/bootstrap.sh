#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# One-time cluster bootstrap: 
# 1. Installs Argo CD via Helm
# 2. Applies the Root Application (App-of-Apps)
# ==============================================================================

# Variables - Update these or export them in your shell
CLUSTER_NAME="${CLUSTER_NAME:-atos-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ARGOCD_NAMESPACE="argocd"
# Helm Chart version for Argo CD (Check https://github.com/argoproj/argo-helm/releases)
ARGOCD_CHART_VERSION="7.7.1" 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Ensure Kubeconfig is current
echo "==> Configuring kubeconfig for cluster '${CLUSTER_NAME}' in '${AWS_REGION}'"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

# 2. Prepare Namespace
echo "==> Creating '${ARGOCD_NAMESPACE}' namespace"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 3. Install Argo CD via Helm
echo "==> Adding Argo Helm Repository"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "==> Installing/Upgrading Argo CD (Chart v${ARGOCD_CHART_VERSION})"
# We install the core Argo CD here.
# Note: We do NOT install the Image Updater here because it will be
# managed declaratively by the root-application.yaml.
#
# server.service.type=LoadBalancer  → creates an AWS NLB so the UI is
#   reachable from your browser without kubectl port-forward.
# The NLB annotation switches from the legacy CLB to a Network Load
#   Balancer (recommended on EKS).
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --set server.extraArgs={--insecure} \
  --set server.service.type=LoadBalancer \
  --set server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --wait

# 4. Apply the Root Application
echo "==> Applying the root Application (The Seed)"
# This file triggers: root -> platform-apps -> image-updater & workloads
kubectl apply -f "${SCRIPT_DIR}/root-application.yaml"

echo "===================================================="
echo "Bootstrap Complete!"
echo "==> Argo CD is installing the Platform and Workloads."
echo ""
echo "==> Waiting for the ArgoCD LoadBalancer hostname (may take ~60 s)..."
LB_HOSTNAME=""
for i in $(seq 1 30); do
  LB_HOSTNAME=$(kubectl -n "${ARGOCD_NAMESPACE}" get svc argocd-server \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "${LB_HOSTNAME}" ]; then
    break
  fi
  sleep 5
done

if [ -n "${LB_HOSTNAME}" ]; then
  echo "==> ArgoCD UI: http://${LB_HOSTNAME}"
else
  echo "==> LB hostname not yet assigned. Run this to check later:"
  echo "    kubectl -n ${ARGOCD_NAMESPACE} get svc argocd-server"
fi

echo ""
echo "==> To get your initial admin password:"
echo "    kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "===================================================="