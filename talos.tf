# ============================================================================
# Talos Machine Secrets
# ============================================================================

resource "talos_machine_secrets" "this" {}

# ============================================================================
# Talos Machine Configuration
# ============================================================================

# Control Plane Configuration
data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = concat(
    # Essential patch: Add load balancer IP and FQDN to certificate SANs
    # This is required for API access through the load balancer
    [
      yamlencode({
        machine = {
          certSANs = concat(
            [openstack_networking_floatingip_v2.controlplane_lb.address],
            var.api_server_fqdn != null ? [var.api_server_fqdn] : []
          )
        }
      })
    ],
    # User-provided patches (optional)
    var.talos_controlplane_config_patches != null ? var.talos_controlplane_config_patches : []
  )
}

# Worker Configuration (per pool)
data "talos_machine_configuration" "workers" {
  for_each = var.workers

  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = local.worker_config_patches[each.key]
}

# ============================================================================
# Talos Configuration Application
# ============================================================================

resource "talos_machine_configuration_apply" "controlplane" {
  count = var.controlplane.count

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    data.talos_machine_configuration.controlplane.machine_configuration
  )
  endpoint = local.cluster_endpoint
  node = (
    openstack_compute_instance_v2.controlplane[count.index].
    network[0].fixed_ip_v4
  )

  depends_on = [openstack_compute_instance_v2.controlplane]
}

resource "talos_machine_configuration_apply" "workers" {
  for_each = local.worker_instances_map

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    data.talos_machine_configuration.workers[each.value.pool_name].
    machine_configuration
  )
  endpoint = local.cluster_endpoint
  node = (
    openstack_compute_instance_v2.workers[each.key].network[0].fixed_ip_v4
  )

  depends_on = [openstack_compute_instance_v2.workers]
}

# ============================================================================
# Talos Bootstrap
# ============================================================================

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.cluster_endpoint
  node = (
    openstack_compute_instance_v2.controlplane[0].network[0].fixed_ip_v4
  )

  depends_on = [talos_machine_configuration_apply.controlplane]
}

# ============================================================================
# Kubeconfig Generation
# ============================================================================

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.cluster_endpoint
  node = (
    openstack_compute_instance_v2.controlplane[0].network[0].fixed_ip_v4
  )

  depends_on = [talos_machine_bootstrap.this]
}
