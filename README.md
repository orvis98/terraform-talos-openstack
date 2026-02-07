# Talos Kubernetes on OpenStack

Terraform module for deploying Talos Linux Kubernetes clusters on OpenStack.

## Requirements

- Terraform >= 1.0
- OpenStack credentials configured (`clouds.yaml` or environment variables)

## Quick Start

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name          = "my-cluster"
  external_network_name = "ext-net"

  controlplane = {
    count       = 1
    flavor_name = "m1.large"
  }
}
```

## Variables

### Required Variables

| Name | Type | Description |
|------|------|-------------|
| `cluster_name` | `string` | Name of the Talos cluster |
| `external_network_name` | `string` | OpenStack external network name for floating IP allocation |
| `controlplane` | `object` | Control plane configuration (see below) |

### Optional Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `talos_version` | `string` | `"v1.12.2"` | Talos Linux version |
| `subnet_cidr` | `string` | `"192.168.1.0/24"` | CIDR block for the subnet (only used when creating new subnet) |
| `dns_nameservers` | `list(string)` | `["8.8.8.8", "8.8.4.4"]` | DNS servers for the subnet |
| `existing_router_id` | `string` | `null` | ID of existing router (creates network + subnet attached to it) |
| `existing_subnet_id` | `string` | `null` | ID of existing subnet (uses existing network + router) |
| `dns_zone_id` | `string` | `null` | OpenStack DNS zone ID for creating API server DNS records |
| `api_server_fqdn` | `string` | `null` | FQDN for API server (required if `dns_zone_id` is set) |
| `workers` | `map(object)` | `{}` | Worker node pool configurations (see below) |
| `talos_controlplane_config_patches` | `list(string)` | `null` | YAML config patches for control plane nodes |
| `talos_worker_config_patches` | `list(string)` | `[]` | YAML config patches for all worker nodes |

### Control Plane Configuration

The `controlplane` object requires these fields:

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `count` | `number` | `1` | No | Number of control plane nodes (must be odd: 1, 3, 5, etc.) |
| `flavor_name` | `string` | - | Yes* | OpenStack flavor name |
| `flavor_id` | `string` | - | Yes* | OpenStack flavor ID (overrides `flavor_name`) |
| `use_volume` | `bool` | `true` | No | Use persistent volumes (false for ephemeral storage) |
| `boot_volume_size` | `number` | `32` | No | Boot volume size in GB (minimum 10 GB) |
| `volume_type` | `string` | `null` | No | Volume type (e.g., ssd, hdd) |
| `talos_extensions` | `list(string)` | `[]` | No | Talos system extensions |

*Either `flavor_name` or `flavor_id` must be specified.

Example:
```hcl
controlplane = {
  count            = 3
  flavor_name      = "m1.large"
  use_volume       = true
  boot_volume_size = 50
  talos_extensions = ["siderolabs/iscsi-tools"]
}
```

### Worker Pool Configuration

The `workers` variable is a map where each key is the pool name and the value has the same structure as `controlplane`, plus:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `config_patches` | `list(string)` | `[]` | Pool-specific YAML config patches |

Example:
```hcl
workers = {
  general = {
    count       = 3
    flavor_name = "m1.xlarge"
  }
  gpu = {
    count            = 2
    flavor_name      = "g1.large"
    talos_extensions = ["siderolabs/nvidia-container-toolkit"]
  }
}
```

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| `controlplane_lb_ip` | Load balancer public IP address | No |
| `controlplane_lb_private_ip` | Load balancer private VIP address | No |
| `api_server_endpoint` | Kubernetes API server URL | No |
| `talosconfig` | Talos client configuration | Yes |
| `kubeconfig` | Kubernetes client configuration | Yes |
| `ccm_app_credential_id` | Cloud Controller Manager credential ID | Yes |
| `ccm_app_credential_secret` | Cloud Controller Manager credential secret | Yes |
| `cinder_csi_app_credential_id` | Cinder CSI credential ID | Yes |
| `cinder_csi_app_credential_secret` | Cinder CSI credential secret | Yes |

## Networking Options

The module supports three networking configurations:

### 1. Create All Resources (Default)

Don't specify `existing_router_id` or `existing_subnet_id`. The module creates:
- Router with gateway to external network
- Network
- Subnet with specified CIDR

```hcl
# No networking variables needed
```

### 2. Use Existing Router

Specify `existing_router_id`. The module creates:
- Network
- Subnet attached to the existing router

```hcl
existing_router_id = "router-uuid"
```

### 3. Use Existing Subnet

Specify `existing_subnet_id`. The module uses the existing subnet (and its network and router).

```hcl
existing_subnet_id = "subnet-uuid"
```

## Talos Extensions

Extensions add functionality to Talos nodes. The module automatically includes `siderolabs/qemu-guest-agent` on all nodes.

Common extensions:
- `siderolabs/iscsi-tools` - iSCSI initiator for Cinder volumes
- `siderolabs/util-linux-tools` - Additional Linux utilities
- `siderolabs/nvidia-container-toolkit` - NVIDIA GPU support
- `siderolabs/intel-ucode` - Intel CPU microcode
- `siderolabs/amd-ucode` - AMD CPU microcode

The module creates separate Glance images for each unique extension combination.

## Configuration Patches

The module automatically applies one essential patch:
- Certificate SANs (load balancer IP + optional FQDN)

Add custom patches using `talos_controlplane_config_patches` or `talos_worker_config_patches`:

```hcl
talos_controlplane_config_patches = [<<EOF
cluster:
  proxy:
    disabled: true
  network:
    cni:
      name: none
machine:
  features:
    kubePrism:
      enabled: true
      port: 7445
EOF
]
```

## Security Groups

### Control Plane
- **Ingress**: 6443 (K8s API), 50000 (Talos API), all traffic from subnet
- **Egress**: All traffic

### Workers
- **Ingress**: 50000 (Talos API), all traffic from subnet
- **Egress**: All traffic

## Load Balancer

The module creates an OpenStack load balancer with:
- Port 6443: Kubernetes API (TCP, ROUND_ROBIN, health checks every 5s)
- Port 50000: Talos API (TCP, ROUND_ROBIN, health checks every 5s)
- Floating IP for external access
- Optional DNS record

## Examples

### Minimal Single-Node Cluster

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name          = "demo"
  external_network_name = "ext-net"

  controlplane = {
    count       = 1
    flavor_name = "m1.medium"
  }
}
```

### Production HA Cluster

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name  = "production"
  talos_version = "v1.12.2"

  external_network_name = "ext-net"
  subnet_cidr           = "192.168.1.0/24"
  dns_zone_id           = "zone-uuid"
  api_server_fqdn       = "api.production.example.com"

  controlplane = {
    count            = 3
    flavor_name      = "m1.large"
    use_volume       = true
    boot_volume_size = 50
    talos_extensions = ["siderolabs/iscsi-tools"]
  }

  workers = {
    general = {
      count       = 5
      flavor_name = "m1.xlarge"
    }
    gpu = {
      count            = 2
      flavor_name      = "g1.large"
      talos_extensions = ["siderolabs/nvidia-container-toolkit"]
    }
  }
}
```

### Using Existing Router

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name          = "existing-router"
  external_network_name = "ext-net"
  existing_router_id    = "router-uuid"

  controlplane = {
    count       = 3
    flavor_name = "m1.large"
  }
}
```

### Using Existing Subnet

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name          = "existing-subnet"
  external_network_name = "ext-net"
  existing_subnet_id    = "subnet-uuid"

  controlplane = {
    count       = 3
    flavor_name = "m1.large"
  }
}
```

### Ephemeral Storage

```hcl
module "talos_cluster" {
  source = "github.com/yourusername/terraform-openstack-talos"

  cluster_name          = "ephemeral"
  external_network_name = "ext-net"

  controlplane = {
    count       = 1
    flavor_name = "m1.large-20GB"
    use_volume  = false
  }
}
```

## Accessing the Cluster

After deployment:

### Export Talosconfig

```bash
terraform output -raw talosconfig > talosconfig
export TALOSCONFIG=$PWD/talosconfig
```

Verify Talos cluster:
```bash
talosctl health
talosctl dashboard
```

### Export Kubeconfig

```bash
terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=$PWD/kubeconfig
```

Verify Kubernetes cluster:
```bash
kubectl get nodes
kubectl get pods -A
```

## Contributing

Contributions are welcome! Please follow these guidelines:

### Reporting Issues

- Check existing issues before creating a new one
- Include Terraform version, provider versions, and OpenStack environment details
- Provide minimal reproduction steps
- Include relevant error messages and logs

### Pull Requests

- Fork the repository and create a feature branch
- Follow existing code style and conventions
- Add or update tests if applicable
- Update documentation (README, variable descriptions) for any changes
- Ensure `terraform fmt` and `terraform validate` pass
- Write clear commit messages

### Development

To test changes locally:

```bash
# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Run plan to check for issues
terraform plan
```

### Code Style

- Use descriptive variable and resource names
- Add comments for complex logic
- Group related resources in the same file
- Keep consistent formatting with existing code

## License

Apache License 2.0
