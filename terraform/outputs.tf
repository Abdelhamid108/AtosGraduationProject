output "vpc_id" {
  description = "ID of the provisioned VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnets"
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private API endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "bastion_instance_id" {
  description = "Instance ID of the Bastion Jump Host"
  value       = module.compute.bastion_instance_id
}

output "ssm_connect_command" {
  description = "AWS CLI command to connect to the Bastion host via SSM"
  value       = module.compute.ssm_connect_command
}

output "kubeconfig_update_command" {
  description = "Command to run inside the Bastion to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
