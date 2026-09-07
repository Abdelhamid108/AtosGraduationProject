terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {

    bucket       = "petclinic-app-tfstate-069089526123-us-east-1-an"
    key          = "petclinic-app/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  dynamic "assume_role" {
    for_each = var.terraform_role_arn != null ? [var.terraform_role_arn] : []
    content {
      role_arn     = assume_role.value
      session_name = "TerraformProvisioningSession"
      duration     = "1h"
    }
  }

  default_tags {
    tags = {
      Project     = "AtosGraduationProject"
      Environment = var.environment
      Terraform   = "true"
    }
  }
}
 

