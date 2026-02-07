# ============================================================================
# OpenStack Data Sources
# ============================================================================

data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

data "openstack_networking_subnet_v2" "existing" {
  count     = var.existing_subnet_id != null ? 1 : 0
  subnet_id = var.existing_subnet_id
}

data "openstack_compute_flavor_v2" "controlplane" {
  count = var.controlplane.flavor_name != null ? 1 : 0
  name  = var.controlplane.flavor_name
}

data "openstack_compute_flavor_v2" "workers" {
  for_each = {
    for pool_name, pool_config in var.workers :
    pool_name => pool_config
    if pool_config.flavor_name != null
  }
  name = each.value.flavor_name
}

# ============================================================================
# Talos Data Sources
# ============================================================================

# Create schematics for each unique extension set
resource "talos_image_factory_schematic" "images" {
  for_each = toset(local.unique_extension_sets)

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = split(",", each.key)
      }
    }
  })
}

# Get image URLs for each schematic
data "talos_image_factory_urls" "images" {
  for_each = toset(local.unique_extension_sets)

  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.images[each.key].id
  platform      = "openstack"
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.cluster_endpoint]
  nodes                = local.all_node_ips
}
