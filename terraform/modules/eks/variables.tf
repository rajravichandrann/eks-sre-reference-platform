variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for control-plane ENIs and managed nodes."
  type        = list(string)
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint."
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Managed node group capacity type."
  type        = string
  default     = "ON_DEMAND"
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

variable "tags" {
  description = "Tags applied to module resources."
  type        = map(string)
  default     = {}
}
