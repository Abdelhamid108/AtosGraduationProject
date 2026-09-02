output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "bastion_instance_id" {
  description = "Instance ID of the Bastion host"
  value       = module.compute.bastion_instance_id
}

output "ssm_connect_command" {
  description = "AWS CLI command to connect to Bastion host via SSM"
  value       = module.compute.ssm_connect_command
}

output "kubeconfig_update_command" {
  description = "Command to configure kubectl credentials for EKS"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

output "ecr_repository_url" {
  description = "URL of the Amazon ECR repository for PetClinic"
  value       = aws_ecr_repository.petclinic.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the Amazon ECR repository"
  value       = aws_ecr_repository.petclinic.arn
}

output "bastion_role_arn" {
  description = "IAM Role ARN of the Bastion host"
  value       = module.iam.bastion_role_arn
}

output "ebs_csi_role_arn" {
  description = "IAM Role ARN created for AWS EBS CSI Driver"
  value       = module.iam.ebs_csi_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN created for AWS Load Balancer Controller"
  value       = module.iam.alb_controller_role_arn
}


output "karpenter_node_role_name" {
  description = "IAM Role Name for Karpenter EC2NodeClass"
  value       = module.eks.karpenter_node_role_name
}

output "karpenter_queue_name" {
  description = "SQS Interruption Queue Name for Karpenter Helm values"
  value       = module.eks.karpenter_queue_name
}
