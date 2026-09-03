output "bastion_instance_id" {
  description = "Instance ID of the Bastion host"
  value       = aws_instance.bastione.id
}

output "bastion_security_group_id" {
  description = "Security Group ID of the Bastion host"
  value       = aws_security_group.bastion_sg.id
}

output "ssm_connect_command" {
  description = "AWS CLI command to connect to the Bastion host via SSM"
  value       = "aws ssm start-session --target ${aws_instance.bastione.id}"
}
