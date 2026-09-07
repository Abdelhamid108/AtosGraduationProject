output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = module.eks.node_security_group_id
}

output "karpenter_node_role_name" {
  description = "IAM Role Name for EC2 instances launched by Karpenter"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_role_arn" {
  description = "IAM Role ARN for EC2 instances launched by Karpenter"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_queue_name" {
  description = "SQS Interruption Queue Name for Karpenter Spot & event handling"
  value       = module.karpenter.queue_name
}

output "karpenter_queue_arn" {
  description = "SQS Interruption Queue ARN for Karpenter"
  value       = module.karpenter.queue_arn
}
