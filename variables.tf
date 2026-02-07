# ============================================================================
# Cluster Configuration
# ============================================================================

variable "cluster_name" {
  type        = string
  description = "Name of the Talos cluster"
}

variable "talos_version" {
  type        = string
  default     = "v1.12.2"
  description = "Version of Talos Linux to deploy"
}


variable "talos_controlplane_config_patches" {
  type        = list(string)
  default     = null
  description = <<-EOT
    Optional list of YAML-encoded Talos configuration patches for control plane nodes.

    The module automatically applies one essential patch:
    - Certificate SANs (load balancer IP + optional FQDN)

    Use this variable to add additional configuration like:
    - CNI configuration (e.g., disable kube-proxy, set CNI to none)
    - KubePrism settings (local API load balancer)
    - Discovery settings
    - Kubelet extra arguments

    Example:
    talos_controlplane_config_patches = [
      yamlencode({
        cluster = {
          proxy = {
            disabled = true  # Disable kube-proxy for CNI proxy replacement
          }
          network = {
            cni = {
              name = "none"  # Don't install default CNI
            }
          }
        }
        machine = {
          features = {
            kubePrism = {
              enabled = true
              port    = 7445
            }
          }
        }
      })
    ]
  EOT
}

variable "talos_worker_config_patches" {
  type        = list(string)
  default     = []
  description = <<-EOT
    List of YAML-encoded Talos configuration patches for all worker nodes.
    These patches are applied to all worker pools in addition to any
    pool-specific patches.

    Example:
    talos_worker_config_patches = [
      yamlencode({
        machine = {
          kubelet = {
            extraArgs = {
              max-pods = "250"
            }
          }
        }
      })
    ]
  EOT
}

# ============================================================================
# Networking Configuration
# ============================================================================

variable "external_network_name" {
  type        = string
  description = "Name of the external network for the router gateway"
}

variable "existing_router_id" {
  type        = string
  default     = null
  description = <<-EOT
    ID of an existing router.
    If provided, a new network and subnet will be created and attached to this router.
    Cannot be combined with existing_subnet_id.
  EOT
}

variable "existing_subnet_id" {
  type        = string
  default     = null
  description = <<-EOT
    ID of an existing subnet.
    If provided, the existing subnet (and its network and router) will be used.
    Cannot be combined with existing_router_id.
  EOT
}

variable "subnet_cidr" {
  type        = string
  default     = "192.168.1.0/24"
  description = "CIDR block for the subnet"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block (e.g., 192.168.1.0/24)."
  }
}

variable "dns_nameservers" {
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
  description = "List of DNS nameservers for the subnet"
}

# ============================================================================
# DNS Configuration (Optional)
# ============================================================================

variable "dns_zone_id" {
  type        = string
  default     = null
  description = <<-EOT
    ID of an existing DNS zone for creating API server DNS records.
    If not provided, no DNS records will be created.
  EOT
}

variable "api_server_fqdn" {
  type        = string
  default     = null
  description = <<-EOT
    Fully qualified domain name for the API server (e.g., api.example.com).
    Required if dns_zone_id is provided.
  EOT
}

# ============================================================================
# Control Plane Configuration
# ============================================================================

variable "controlplane" {
  type = object({
    count            = optional(number, 1)
    flavor_name      = optional(string)
    flavor_id        = optional(string)
    use_volume       = optional(bool, true)
    boot_volume_size = optional(number, 32)
    volume_type      = optional(string)
    talos_extensions = optional(list(string), [])
  })
  description = <<-EOT
    Control plane configuration.
    - count: Number of control plane nodes
    - flavor_name: OpenStack flavor name (mutually exclusive with flavor_id)
    - flavor_id: OpenStack flavor ID (takes precedence over flavor_name)
    - use_volume: Use volume storage (false for ephemeral storage)
    - boot_volume_size: Boot volume size in GB
    - volume_type: Volume type (e.g., ssd, hdd)
    - talos_extensions: List of Talos extensions for control plane nodes

    Common extensions:
    - siderolabs/qemu-guest-agent (included by default)
    - siderolabs/iscsi-tools
    - siderolabs/util-linux-tools
    - siderolabs/nvidia-container-toolkit
    - siderolabs/intel-ucode
    - siderolabs/amd-ucode
  EOT

  validation {
    condition     = var.controlplane.flavor_name != null || var.controlplane.flavor_id != null
    error_message = "Either flavor_name or flavor_id must be specified for control plane."
  }

  validation {
    condition     = var.controlplane.count > 0
    error_message = "Control plane count must be at least 1."
  }

  validation {
    condition     = var.controlplane.count % 2 == 1
    error_message = "Control plane count should be an odd number (1, 3, 5, etc.) for proper etcd quorum."
  }

  validation {
    condition     = var.controlplane.boot_volume_size >= 10
    error_message = "Boot volume size must be at least 10 GB."
  }
}

# ============================================================================
# Worker Configuration
# ============================================================================

variable "workers" {
  type = map(object({
    count            = optional(number, 1)
    flavor_name      = optional(string)
    flavor_id        = optional(string)
    use_volume       = optional(bool, true)
    boot_volume_size = optional(number, 32)
    volume_type      = optional(string)
    config_patches   = optional(list(string), [])
    talos_extensions = optional(list(string), [])
  }))
  default     = {}
  description = <<-EOT
    Worker node pool configurations. Map key is the worker pool name.
    Each pool supports the same configuration as control plane:
    - count: Number of worker nodes in this pool
    - flavor_name: OpenStack flavor name (mutually exclusive with flavor_id)
    - flavor_id: OpenStack flavor ID (takes precedence over flavor_name)
    - use_volume: Use volume storage (false for ephemeral storage)
    - boot_volume_size: Boot volume size in GB
    - volume_type: Volume type (e.g., ssd, hdd)
    - config_patches: Pool-specific Talos configuration patches
    - talos_extensions: List of Talos extensions for this worker pool

    Example:
    workers = {
      gpu = {
        count       = 2
        flavor_name = "g1.large"
        talos_extensions = [
          "siderolabs/nvidia-container-toolkit"
        ]
      }
      storage = {
        count       = 3
        flavor_name = "m1.large"
        talos_extensions = [
          "siderolabs/iscsi-tools"
        ]
      }
    }
  EOT
}
