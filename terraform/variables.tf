variable "aws_region" {
  description = "AWS region used by the reference platform."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Stable project prefix used for resource naming."
  type        = string
  default     = "eks-sre-reference"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per Availability Zone."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per Availability Zone."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for the lab. Set false for one NAT gateway per AZ."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.35"
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Prefer a single trusted /32."
  type        = list(string)

  validation {
    condition     = length(var.cluster_public_access_cidrs) > 0 && !contains(var.cluster_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one trusted CIDR and do not use 0.0.0.0/0."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Managed node group capacity type: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum managed node group size."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Desired managed node group size."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum managed node group size."
  type        = number
  default     = 4
}

variable "control_plane_log_retention_days" {
  description = "CloudWatch retention for EKS control-plane logs."
  type        = number
  default     = 7
}

variable "ecr_repository_names" {
  description = "ECR repositories created for application images."
  type        = set(string)
  default     = ["eks-sre-reference-app"]
}

variable "ecr_force_delete" {
  description = "Allow Terraform to delete non-empty ECR repos. Useful for a disposable lab."
  type        = bool
  default     = true
}
