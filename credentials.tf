# ============================================================================
# OpenStack Application Credentials
# ============================================================================
# These credentials are used by Kubernetes components to interact with
# OpenStack services (load balancers, volumes, etc.)

resource "openstack_identity_application_credential_v3" "cloud_controller_manager" {
  name        = "${var.cluster_name}-ccm"
  description = "Application credential for Kubernetes Cloud Controller Manager"

  # CCM does not need to create application credentials itself
  unrestricted = false
}

resource "openstack_identity_application_credential_v3" "cinder_csi" {
  name        = "${var.cluster_name}-cinder-csi"
  description = "Application credential for Cinder CSI driver"

  # CSI does not need to create application credentials itself
  unrestricted = false
}
