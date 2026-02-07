# ============================================================================
# Terraform Configuration
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10"
    }
  }
}
