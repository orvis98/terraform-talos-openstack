# ============================================================================
# Networking Resources
# ============================================================================

resource "openstack_networking_router_v2" "this" {
  count               = var.existing_router_id == null && var.existing_subnet_id == null ? 1 : 0
  name                = "external"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_network_v2" "this" {
  count          = var.existing_subnet_id == null ? 1 : 0
  name           = var.cluster_name
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "this" {
  count           = var.existing_subnet_id == null ? 1 : 0
  name            = "${var.cluster_name}-subnet"
  network_id      = local.network_id
  cidr            = var.subnet_cidr
  ip_version      = 4
  enable_dhcp     = true
  dns_nameservers = var.dns_nameservers
}

resource "openstack_networking_router_interface_v2" "this" {
  count     = var.existing_subnet_id == null ? 1 : 0
  router_id = local.router_id
  subnet_id = local.subnet_id
}


# ============================================================================
# Talos Images
# ============================================================================

# Create an image for each unique extension combination
resource "openstack_images_image_v2" "talos" {
  for_each = toset(local.unique_extension_sets)

  name = format("Talos %s - %s",
    var.talos_version,
    # Create readable suffix from extensions
    length(split(",", each.key)) > 1 ? join(", ", [
      for ext in slice(split(",", each.key), 1, length(split(",", each.key))) :
      replace(ext, "siderolabs/", "")
    ]) : "base"
  )

  image_source_url = data.talos_image_factory_urls.images[each.key].urls.disk_image
  container_format = "bare"
  disk_format      = "raw"
  decompress       = true

  properties = {
    talos_version = var.talos_version
    extension_set = each.key
    schematic_id  = talos_image_factory_schematic.images[each.key].id
  }
}

# ============================================================================
# Security Groups
# ============================================================================

# Control Plane Security Group
resource "openstack_networking_secgroup_v2" "controlplane" {
  name                 = "${var.cluster_name}-controlplane"
  description          = "Security group for Talos control plane nodes"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "controlplane_k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
}

resource "openstack_networking_secgroup_rule_v2" "controlplane_talos_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 50000
  port_range_max    = 50000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
}

resource "openstack_networking_secgroup_rule_v2" "controlplane_subnet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
}

resource "openstack_networking_secgroup_rule_v2" "controlplane_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
}

# Worker Security Group
resource "openstack_networking_secgroup_v2" "workers" {
  name                 = "${var.cluster_name}-workers"
  description          = "Security group for Talos worker nodes"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "workers_talos_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 50000
  port_range_max    = 50000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.workers.id
}

resource "openstack_networking_secgroup_rule_v2" "workers_subnet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.workers.id
}

resource "openstack_networking_secgroup_rule_v2" "workers_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.workers.id
}

# ============================================================================
# Control Plane Instances
# ============================================================================

resource "openstack_blockstorage_volume_v3" "controlplane" {
  count       = var.controlplane.use_volume ? var.controlplane.count : 0
  name        = "${var.cluster_name}-controlplane-${count.index}"
  size        = var.controlplane.boot_volume_size
  image_id    = openstack_images_image_v2.talos[local.controlplane_image_key].id
  volume_type = var.controlplane.volume_type
}

resource "openstack_compute_instance_v2" "controlplane" {
  count           = var.controlplane.count
  name            = "${var.cluster_name}-controlplane-${count.index}"
  flavor_id       = local.controlplane_flavor_id
  image_id        = var.controlplane.use_volume ? null : openstack_images_image_v2.talos[local.controlplane_image_key].id
  security_groups = [openstack_networking_secgroup_v2.controlplane.name]
  user_data       = data.talos_machine_configuration.controlplane.machine_configuration

  network {
    uuid = local.network_id
  }

  dynamic "block_device" {
    for_each = var.controlplane.use_volume ? [1] : []
    content {
      uuid                  = openstack_blockstorage_volume_v3.controlplane[count.index].id
      source_type           = "volume"
      destination_type      = "volume"
      boot_index            = 0
      delete_on_termination = true
    }
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# ============================================================================
# Load Balancer
# ============================================================================

resource "openstack_lb_loadbalancer_v2" "controlplane" {
  name          = "${var.cluster_name}-controlplane"
  vip_subnet_id = local.subnet_id
}

resource "openstack_networking_floatingip_v2" "controlplane_lb" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "controlplane_lb" {
  floating_ip = openstack_networking_floatingip_v2.controlplane_lb.address
  port_id     = openstack_lb_loadbalancer_v2.controlplane.vip_port_id

  depends_on = [openstack_networking_router_interface_v2.this]
}

# DNS Record (optional)
resource "openstack_dns_recordset_v2" "api_server" {
  count   = var.dns_zone_id != null ? 1 : 0
  zone_id = var.dns_zone_id
  name    = "${var.api_server_fqdn}."
  type    = "A"
  ttl     = 300
  records = [openstack_networking_floatingip_v2.controlplane_lb.address]
}

# Kubernetes API Listener (port 6443)
resource "openstack_lb_listener_v2" "controlplane_k8s_api" {
  name            = "${var.cluster_name}-k8s-api"
  protocol        = "TCP"
  protocol_port   = 6443
  loadbalancer_id = openstack_lb_loadbalancer_v2.controlplane.id
}

resource "openstack_lb_pool_v2" "controlplane_k8s_api" {
  name        = "${var.cluster_name}-k8s-api"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.controlplane_k8s_api.id
}

resource "openstack_lb_monitor_v2" "controlplane_k8s_api" {
  name        = "${var.cluster_name}-k8s-api"
  pool_id     = openstack_lb_pool_v2.controlplane_k8s_api.id
  type        = "TCP"
  delay       = 5
  timeout     = 3
  max_retries = 3
}

resource "openstack_lb_member_v2" "controlplane_k8s_api" {
  count         = var.controlplane.count
  pool_id       = openstack_lb_pool_v2.controlplane_k8s_api.id
  address       = openstack_compute_instance_v2.controlplane[count.index].network[0].fixed_ip_v4
  protocol_port = 6443
  subnet_id     = local.subnet_id
}

# Talos API Listener (port 50000)
resource "openstack_lb_listener_v2" "controlplane_talos_api" {
  name            = "${var.cluster_name}-talos-api"
  protocol        = "TCP"
  protocol_port   = 50000
  loadbalancer_id = openstack_lb_loadbalancer_v2.controlplane.id
}

resource "openstack_lb_pool_v2" "controlplane_talos_api" {
  name        = "${var.cluster_name}-talos-api"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.controlplane_talos_api.id
}

resource "openstack_lb_monitor_v2" "controlplane_talos_api" {
  name        = "${var.cluster_name}-talos-api"
  pool_id     = openstack_lb_pool_v2.controlplane_talos_api.id
  type        = "TCP"
  delay       = 5
  timeout     = 3
  max_retries = 3
}

resource "openstack_lb_member_v2" "controlplane_talos_api" {
  count         = var.controlplane.count
  pool_id       = openstack_lb_pool_v2.controlplane_talos_api.id
  address       = openstack_compute_instance_v2.controlplane[count.index].network[0].fixed_ip_v4
  protocol_port = 50000
  subnet_id     = local.subnet_id
}

# ============================================================================
# Worker Instances
# ============================================================================

resource "openstack_blockstorage_volume_v3" "workers" {
  for_each = {
    for instance in local.worker_instances :
    instance.key => instance
    if instance.use_volume
  }

  name        = "${var.cluster_name}-worker-${each.value.pool_name}-${each.value.index}"
  size        = each.value.boot_volume_size
  image_id    = openstack_images_image_v2.talos[local.worker_image_keys[each.value.pool_name]].id
  volume_type = each.value.volume_type
}

resource "openstack_compute_instance_v2" "workers" {
  for_each = local.worker_instances_map

  name            = "${var.cluster_name}-worker-${each.value.pool_name}-${each.value.index}"
  flavor_id       = local.worker_flavor_ids[each.value.pool_name]
  image_id        = each.value.use_volume ? null : openstack_images_image_v2.talos[local.worker_image_keys[each.value.pool_name]].id
  security_groups = [openstack_networking_secgroup_v2.workers.name]
  user_data = (
    data.talos_machine_configuration.workers[each.value.pool_name].
    machine_configuration
  )

  network {
    uuid = local.network_id
  }

  dynamic "block_device" {
    for_each = each.value.use_volume ? [1] : []
    content {
      uuid                  = openstack_blockstorage_volume_v3.workers[each.key].id
      source_type           = "volume"
      destination_type      = "volume"
      boot_index            = 0
      delete_on_termination = true
    }
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}
