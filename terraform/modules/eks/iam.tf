module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${var.cluster_name}-ebs-csi-role"

  attach_aws_ebs_csi_policy = true

  associations = {
    main = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = {
    Name      = "${var.cluster_name}-ebs-csi-role"
    Terraform = "true"
  }
}

module "load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${var.cluster_name}-alb-controller-role"

  attach_aws_lb_controller_policy = true

  associations = {
    main = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = {
    Name      = "${var.cluster_name}-alb-controller-role"
    Terraform = "true"
  }
}
