check "node_scaling_bounds" {
  assert {
    condition = (
      var.node_min_size <= var.node_desired_size &&
      var.node_desired_size <= var.node_max_size
    )
    error_message = "Node scaling must satisfy min_size <= desired_size <= max_size."
  }
}
