module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  addons = {
    coredns            = {}
    aws-ebs-csi-driver = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  create_kms_key = true

  endpoint_public_access  = false
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets

  eks_managed_node_groups = {
    cluster-nodes = {
      ami_type       = var.ami_type
      instance_types = var.instance_types

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }

  cluster_security_group_additional_rules = {
    ingress_bastion = {
      source_security_group_id = var.bastion_security_group_id
      description              = "Allow HTTPS from Bastion Host"
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      type                     = "ingress"
    }
  }

  node_security_group_additional_rules = {
    ingress_alb_webhook = {
      description                   = "Allow Control Plane to ALB Webhook"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = {
    Name      = var.cluster_name
    Terraform = "true"
  }
}
