# ============================================================================
# Load Balancer Outputs
# ============================================================================

output "controlplane_lb_ip" {
  description = "Load balancer public IP address for control plane access"
  value       = openstack_networking_floatingip_v2.controlplane_lb.address
}

output "controlplane_lb_private_ip" {
  description = "Load balancer private VIP address for internal access"
  value       = openstack_lb_loadbalancer_v2.controlplane.vip_address
}

output "api_server_endpoint" {
  description = "API server endpoint URL"
  value       = "https://${local.cluster_endpoint}:6443"
}

# ============================================================================
# Client Configuration Outputs
# ============================================================================

output "talosconfig" {
  description = <<-EOT
    Talos client configuration
    Usage: terraform output -raw talosconfig > talosconfig
  EOT
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = <<-EOT
    Kubernetes client configuration
    Usage: terraform output -raw kubeconfig > kubeconfig
  EOT
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

# ============================================================================
# OpenStack Application Credentials
# ============================================================================

output "ccm_app_credential_id" {
  description = "Application credential ID for Cloud Controller Manager"
  value = (
    openstack_identity_application_credential_v3.cloud_controller_manager.id
  )
  sensitive = true
}

output "ccm_app_credential_secret" {
  description = <<-EOT
    Application credential secret for Cloud Controller Manager
  EOT
  value = (
    openstack_identity_application_credential_v3.cloud_controller_manager.secret
  )
  sensitive = true
}

output "cinder_csi_app_credential_id" {
  description = "Application credential ID for Cinder CSI"
  value = (
    openstack_identity_application_credential_v3.cinder_csi.id
  )
  sensitive = true
}

output "cinder_csi_app_credential_secret" {
  description = "Application credential secret for Cinder CSI"
  value = (
    openstack_identity_application_credential_v3.cinder_csi.secret
  )
  sensitive = true
}
