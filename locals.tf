locals {
  # Networking - Use existing resources or create new ones
  router_id = coalesce(
    var.existing_router_id,
    try(openstack_networking_router_v2.this[0].id, null)
  )
  network_id = coalesce(
    var.existing_subnet_id != null ? data.openstack_networking_subnet_v2.existing[0].network_id : null,
    try(openstack_networking_network_v2.this[0].id, null)
  )
  subnet_id = coalesce(
    var.existing_subnet_id,
    try(openstack_networking_subnet_v2.this[0].id, null)
  )

  # Cluster endpoint - Use FQDN if provided, otherwise use load balancer IP
  cluster_endpoint = coalesce(
    var.api_server_fqdn,
    openstack_networking_floatingip_v2.controlplane_lb.address
  )

  # Talos Extensions Management
  # Collect all unique extension combinations from controlplane and workers
  all_extension_sets = merge(
    {
      controlplane = sort(concat(
        ["siderolabs/qemu-guest-agent"],
        [for ext in var.controlplane.talos_extensions : ext if ext != "siderolabs/qemu-guest-agent"]
      ))
    },
    {
      for pool_name, pool_config in var.workers :
      "worker-${pool_name}" => sort(concat(
        ["siderolabs/qemu-guest-agent"],
        [for ext in pool_config.talos_extensions : ext if ext != "siderolabs/qemu-guest-agent"]
      ))
    }
  )

  # Create unique extension sets with deterministic keys
  unique_extension_sets = distinct([
    for k, v in local.all_extension_sets : join(",", v)
  ])

  # Map each node type to its extension set key
  extension_set_keys = {
    for k, v in local.all_extension_sets :
    k => join(",", v)
  }

  # Map extension set key to schematic ID (populated after data sources)
  controlplane_image_key = local.extension_set_keys["controlplane"]

  worker_image_keys = {
    for pool_name in keys(var.workers) :
    pool_name => local.extension_set_keys["worker-${pool_name}"]
  }

  # Control plane flavor resolution
  controlplane_flavor_id = coalesce(
    var.controlplane.flavor_id,
    try(data.openstack_compute_flavor_v2.controlplane[0].id, null)
  )

  # Worker pool expansion - flatten worker pools into individual instances
  worker_instances = flatten([
    for pool_name, pool_config in var.workers : [
      for i in range(pool_config.count) : {
        pool_name        = pool_name
        index            = i
        key              = "${pool_name}-${i}"
        flavor_name      = pool_config.flavor_name
        flavor_id        = pool_config.flavor_id
        use_volume       = pool_config.use_volume
        boot_volume_size = pool_config.boot_volume_size
        volume_type      = pool_config.volume_type
        config_patches   = pool_config.config_patches
        talos_extensions = pool_config.talos_extensions
      }
    ]
  ])

  worker_instances_map = {
    for instance in local.worker_instances :
    instance.key => instance
  }

  # Worker flavor resolution per pool
  worker_flavor_ids = {
    for pool_name, pool_config in var.workers :
    pool_name => coalesce(
      pool_config.flavor_id,
      try(data.openstack_compute_flavor_v2.workers[pool_name].id, null)
    )
  }

  # Worker config patches per pool (global + pool-specific)
  worker_config_patches = {
    for pool_name, pool_config in var.workers :
    pool_name => concat(
      var.talos_worker_config_patches,
      pool_config.config_patches
    )
  }

  # Node IP addresses for Talos client configuration
  controlplane_ips = [
    for i in range(var.controlplane.count) :
    openstack_compute_instance_v2.controlplane[i].network[0].fixed_ip_v4
  ]

  worker_ips = [
    for key, instance in openstack_compute_instance_v2.workers :
    instance.network[0].fixed_ip_v4
  ]

  all_node_ips = concat(local.controlplane_ips, local.worker_ips)
}
