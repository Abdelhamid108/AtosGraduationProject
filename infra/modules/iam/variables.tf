variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "ssm_parameter_prefix" {
  description = "Prefix for application SSM Parameter Store and Secrets Manager access"
  type        = string
  default     = "/atos/petclinic"
}
