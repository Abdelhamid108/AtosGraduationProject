resource "aws_ecr_repository" "petclinic" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = var.ecr_repository_name
    Application = "SpringPetClinic"
    Terraform   = "true"
  }
}

resource "aws_ecr_lifecycle_policy" "petclinic_policy" {
  repository = aws_ecr_repository.petclinic.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 tagged release/build images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "build-", "release-", "main-", "dev-", "test-", "prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}