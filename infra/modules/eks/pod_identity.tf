# EKS Pod Identity Associations for Platform Controllers & Application Workloads
# Associated directly with the EKS cluster to guarantee correct lifecycle ordering

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = var.alb_controller_role_arn

  tags = {
    Name      = "${var.cluster_name}-alb-controller-pod-identity"
    Terraform = "true"
  }
}


resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = var.external_secrets_role_arn

  tags = {
    Name      = "${var.cluster_name}-external-secrets-pod-identity"
    Terraform = "true"
  }
}

resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = module.eks.cluster_name
  namespace       = "argocd"
  service_account = "argocd-image-updater"
  role_arn        = var.image_updater_role_arn

  tags = {
    Name      = "${var.cluster_name}-image-updater-pod-identity"
    Terraform = "true"
  }
}