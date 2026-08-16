locals {
  name = "${var.project_name}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "eks-sre-reference-platform"
  }
}

module "vpc" {
  source = "./modules/vpc"

  name                 = "${local.name}-vpc"
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway

  tags = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"

  repository_names     = var.ecr_repository_names
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  force_delete         = var.ecr_force_delete

  tags = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name                = local.name
  kubernetes_version          = var.kubernetes_version
  private_subnet_ids          = module.vpc.private_subnet_ids
  cluster_public_access_cidrs = var.cluster_public_access_cidrs

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size

  control_plane_log_retention_days = var.control_plane_log_retention_days

  tags = local.common_tags
}
