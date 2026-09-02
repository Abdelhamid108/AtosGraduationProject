# EKS Pod Identity Roles (Associations are managed by the EKS module once cluster exists)

# 1. AWS EBS CSI Driver Pod Identity Role
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name            = "${var.cluster_name}-ebs-csi-role"
  use_name_prefix = false

  attach_aws_ebs_csi_policy = true

  tags = {
    Name      = "${var.cluster_name}-ebs-csi-role"
    Terraform = "true"
  }
}

# 2. AWS Load Balancer Controller Pod Identity Role
module "load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name            = "${var.cluster_name}-alb-controller-role"
  use_name_prefix = false

  attach_aws_lb_controller_policy = true

  tags = {
    Name      = "${var.cluster_name}-alb-controller-role"
    Terraform = "true"
  }
}

# 3. External Secrets Operator Pod Identity Role
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  name            = "${var.cluster_name}-external-secrets-role"
  use_name_prefix = false

  attach_external_secrets_policy        = true
  external_secrets_ssm_parameter_arns   = ["arn:aws:ssm:${var.aws_region}:*:parameter${var.ssm_parameter_prefix}/*"]
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:atos/petclinic/*"]
  external_secrets_kms_key_arns         = ["arn:aws:kms:${var.aws_region}:*:key/*"]
  external_secrets_create_permission    = false # Set to true only if ESO creates secrets in AWS

  tags = {
    Name      = "${var.cluster_name}-external-secrets-role"
    Terraform = "true"
  }
}

resource "aws_iam_policy" "image_updater_ecr_policy" {
  name        = "${var.cluster_name}-image-updater-ecr"
  description = "Allows Argo CD Image Updater to pull images from Amazon ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name      = "${var.cluster_name}-image-updater-ecr"
    Terraform = "true"
  }
}

module "image_updater_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  name            = "${var.cluster_name}-image-updater-role"
  use_name_prefix = false

  additional_policy_arns = {
    ecr_access = aws_iam_policy.image_updater_ecr_policy.arn
  }

  tags = {
    Name      = "${var.cluster_name}-image-updater-role"
    Terraform = "true"
  }
}