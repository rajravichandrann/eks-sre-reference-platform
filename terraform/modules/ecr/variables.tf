variable "repository_names" {
  description = "ECR repository names."
  type        = set(string)
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability setting."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable ECR basic scan-on-push."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Delete images automatically when Terraform destroys the repository."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to ECR repositories."
  type        = map(string)
  default     = {}
}
