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
ARGOCD_CHART_VERSION="10.6.0" 

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
  --set server.service.type=LoadBalancer
  # No NLB annotation → defaults to Classic ELB (v1), which this account supports.

# 4. Apply the Root Application
echo "==> Applying the root Application (The Seed)"
# This file triggers: root -> platform-apps -> image-updater & workloads
kubectl apply -f "${SCRIPT_DIR}/root-application.yaml"

echo "===================================================="
echo "Bootstrap Complete!"
echo "==> Argo CD is installing the Platform and Workloads."
echo ""
echo "==> Access the ArgoCD UI via kubectl port-forward:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:80 --address 0.0.0.0 &"
echo "    Then open http://localhost:8080 (or SSH-tunnel from your local machine)"
echo ""
echo "==> To get your initial admin password:"
echo "    kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "===================================================="