# ============================================================================
# Precondition Checks
# ============================================================================
# These checks validate configuration before resources are created

resource "null_resource" "validate_worker_pools" {
  for_each = var.workers

  lifecycle {
    precondition {
      condition     = each.value.flavor_name != null || each.value.flavor_id != null
      error_message = "Worker pool '${each.key}': Either flavor_name or flavor_id must be specified."
    }

    precondition {
      condition     = each.value.count > 0
      error_message = "Worker pool '${each.key}': count must be at least 1."
    }

    precondition {
      condition     = each.value.boot_volume_size >= 10
      error_message = "Worker pool '${each.key}': boot_volume_size must be at least 10 GB."
    }
  }
}

resource "null_resource" "validate_networking" {
  lifecycle {
    precondition {
      condition = (
        # Valid: nothing specified (create all)
        (var.existing_router_id == null && var.existing_subnet_id == null) ||
        # Valid: only router specified (create network + subnet)
        (var.existing_router_id != null && var.existing_subnet_id == null) ||
        # Valid: only subnet specified (use existing subnet)
        (var.existing_router_id == null && var.existing_subnet_id != null)
      )
      error_message = "Invalid networking configuration. Valid options: 1) Specify nothing (creates all), 2) Specify only existing_router_id (creates network + subnet), 3) Specify only existing_subnet_id (uses existing subnet)."
    }

    precondition {
      condition     = var.dns_zone_id == null || var.api_server_fqdn != null
      error_message = "api_server_fqdn is required when dns_zone_id is provided."
    }
  }
}
