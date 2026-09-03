module "vpc" {
  source = "./modules/vpc"

  vpc_name        = var.vpc_name
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  cluster_name    = var.cluster_name
}

module "iam" {
  source = "./modules/iam"

  cluster_name         = var.cluster_name
  aws_region           = var.aws_region
  ssm_parameter_prefix = var.ssm_parameter_prefix
}

module "compute" {
  source = "./modules/compute"

  cluster_name              = var.cluster_name
  vpc_id                    = module.vpc.vpc_id
  subnet_id                 = module.vpc.public_subnets[0]
  instance_type             = var.bastion_instance_type
  iam_instance_profile_name = module.iam.bastion_instance_profile_name
}

module "eks" {
  source = "./modules/eks"

  cluster_name             = var.cluster_name
  cluster_version          = var.cluster_version
  vpc_id                   = module.vpc.vpc_id
  private_subnets          = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  ami_type       = var.ami_type
  instance_types = var.instance_types
  min_size       = var.min_size
  max_size       = var.max_size
  desired_size   = var.desired_size

  bastion_security_group_id = module.compute.bastion_security_group_id
  bastion_role_arn          = module.iam.bastion_role_arn
  ebs_csi_role_arn          = module.iam.ebs_csi_role_arn
  external_secrets_role_arn = module.iam.external_secrets_role_arn
  image_updater_role_arn    = module.iam.image_updater_role_arn
  alb_controller_role_arn   = module.iam.alb_controller_role_arn
}

