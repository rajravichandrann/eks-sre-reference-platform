check "subnet_counts_match_azs" {
  assert {
    condition = (
      length(var.public_subnet_cidrs) == length(var.availability_zones) &&
      length(var.private_subnet_cidrs) == length(var.availability_zones)
    )
    error_message = "Provide exactly one public and one private subnet CIDR per Availability Zone."
  }
}
