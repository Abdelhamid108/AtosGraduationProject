variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where the bastion is deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the bastion (Public subnet)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name attached to the bastion host"
  type        = string
}
