output "bastion_role_arn" {
  description = "IAM Role ARN of the Bastion host"
  value       = aws_iam_role.bastion_role.arn
}

output "bastion_instance_profile_name" {
  description = "IAM Instance Profile Name for the Bastion host"
  value       = aws_iam_instance_profile.bastion_profile.name
}

output "ebs_csi_role_arn" {
  description = "IAM Role ARN for AWS EBS CSI Driver"
  value       = module.ebs_csi_pod_identity.iam_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = module.load_balancer_controller_pod_identity.iam_role_arn
}


output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets"
  value       = module.external_secrets_pod_identity.iam_role_arn
}

output "image_updater_role_arn" {
  description = "IAM Role ARN for Argo CD Image Updater"
  value       = module.image_updater_pod_identity.iam_role_arn
}

