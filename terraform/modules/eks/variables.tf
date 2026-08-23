variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Version of the EKS cluster"
  type        = string
}

variable "ami_type" {
  description = "AMI type for the EKS cluster"
  type        = string
}

variable "instance_types" {
  description = "Instance types for the EKS cluster"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum number of instances for the EKS cluster"
  type        = number
}

variable "max_size" {
  description = "Maximum number of instances for the EKS cluster"
  type        = number
}

variable "desired_size" {
  description = "Desired number of instances for the EKS cluster"
  type        = number
}

variable "vpc_id" {
  description = "ID of the VPC for the EKS cluster"
  type        = string
}

variable "private_subnets" {
  description = "Private subnets for the EKS cluster"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Control plane subnets for the EKS cluster"
  type        = list(string)
}

variable "bastion_security_group_id" {
  description = "Security group ID of the Bastion host to allow access to EKS API"
  type        = string
  default     = null
}