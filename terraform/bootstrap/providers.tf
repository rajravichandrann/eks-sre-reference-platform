provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "eks-sre-reference-platform"
      ManagedBy  = "terraform"
      Component  = "bootstrap"
      Repository = "eks-sre-reference-platform"
    }
  }
}