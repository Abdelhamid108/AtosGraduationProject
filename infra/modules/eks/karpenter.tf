# Karpenter Controller & Node IAM, Pod Identity, and SQS Interruption Queue
# Utilizes the official AWS EKS Karpenter Submodule

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  namespace                       = "karpenter"
  create_pod_identity_association = true
  create_access_entry             = true

  # Use inline policy to avoid AWS managed IAM policy 6144 byte size limit
  enable_inline_policy = true

  # Attach SSM policy to Karpenter nodes for session manager debugging
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Enable SQS queue and EventBridge rules for Spot interruptions and rebalances
  enable_spot_termination = true

  tags = {
    Name        = "${var.cluster_name}-karpenter"
    Application = "Karpenter"
    Terraform   = "true"
  }
}
