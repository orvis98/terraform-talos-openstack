# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

A single root Terraform module that deploys a Talos Linux Kubernetes cluster on OpenStack. It is consumed as a `module` block (see [README.md](README.md) Quick Start), not run standalone. There is no `terraform.tfvars` here — examples are illustrative.

## Commands

Lint runs through Dagger (matches CI in [.github/workflows/lint.yml](.github/workflows/lint.yml)):

```bash
dagger call lint --source .
```

This containerizes `terraform fmt -check -recursive` followed by `terraform init -backend=false` and `terraform validate` ([.dagger/main.go](.dagger/main.go)). Reproduce locally without Dagger:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

To regenerate Dagger bindings after editing [.dagger/main.go](.dagger/main.go): `dagger develop` (in the repo root).

There is no test suite — validation is via `terraform validate`, variable `validation` blocks, and `null_resource` precondition checks in [preconditions.tf](preconditions.tf).

## Architecture

Files are split by concern, not by component. When changing behavior, expect to touch several:

- [variables.tf](variables.tf) — input schema and `validation` blocks (e.g., odd controlplane count, unique `additional_volumes` names, positive sizes).
- [locals.tf](locals.tf) — all derivations. Three patterns dominate here:
  1. **Worker pool flattening.** `var.workers` is `map(object)` keyed by pool name. `local.worker_instances_map` flattens it to per-instance entries keyed `"${pool_name}-${index}"`. Every per-instance resource (`openstack_compute_instance_v2.workers`, `openstack_blockstorage_volume_v3.workers`, `talos_machine_configuration_apply.workers`) iterates this map. New per-worker resources should follow the same pattern.
  2. **Extension set deduplication.** Controlplane and each worker pool can declare `talos_extensions`. `local.all_extension_sets` collapses them; unique sorted comma-joined strings become keys for `talos_image_factory_schematic` / `data.talos_image_factory_urls` / `openstack_images_image_v2.talos`. One Glance image per unique combo, not per pool. `siderolabs/qemu-guest-agent` is force-prepended.
  3. **Additional volumes expansion.** `var.controlplane.additional_volumes` and per-pool `additional_volumes` expand to one Cinder volume per (node × entry), keyed `"${i}-${name}"` for controlplane and `"${pool}-${i}-${name}"` for workers.
- [data.tf](data.tf) — OpenStack data sources + Talos image factory (schematics + URLs) + Talos client config.
- [infrastructure.tf](infrastructure.tf) — networking, security groups, Glance images, instances, load balancer (port 6443 K8s API + port 50000 Talos API), and the `openstack_compute_volume_attach_v2` resources for `additional_volumes`. Note: additional volumes are attached via the Compute API after instance creation, **not** as `block_device` blocks on the instance.
- [talos.tf](talos.tf) — `talos_machine_secrets`, machine config (controlplane + per-pool worker), `talos_machine_configuration_apply`, bootstrap (targets `controlplane[0]` only), and `talos_cluster_kubeconfig`.
- [credentials.tf](credentials.tf) — pre-creates two OpenStack application credentials (CCM, Cinder CSI) and exports them as sensitive outputs. The module does **not** deploy CCM or CSI — consumers wire these creds into their own manifests.
- [preconditions.tf](preconditions.tf) — `null_resource` lifecycle preconditions for cross-variable constraints that can't live in a single `variable.validation`.
- [outputs.tf](outputs.tf) — kubeconfig, talosconfig, LB IP/endpoint, app creds.

### Three networking modes

Selected by which of `existing_router_id` / `existing_subnet_id` is set (mutually exclusive; enforced in [preconditions.tf](preconditions.tf)). [locals.tf](locals.tf) `router_id` / `network_id` / `subnet_id` resolve to either the data-sourced existing value or the freshly created resource via `coalesce` + `try`. New networking-touching code must respect all three modes.

### Cluster endpoint resolution

`local.cluster_endpoint` prefers `var.api_server_fqdn`, falling back to the LB floating IP. It is used both as the Talos cluster endpoint and (for FQDN case) injected into cert SANs alongside the LB IP via an automatic config patch in [talos.tf](talos.tf).

### Instances ignore `user_data` changes

Both `openstack_compute_instance_v2.controlplane` and `.workers` set `lifecycle { ignore_changes = [user_data] }`. Talos config changes are applied in-place via `talos_machine_configuration_apply` — they do **not** rebuild instances. Don't remove these `ignore_changes` without understanding that contract.

### Additional volumes — module boundary

The module only **provisions and attaches** Cinder volumes. Mounting/formatting inside Talos is the caller's responsibility, and they must reference the disk by **serial/WWID**, not guest device name (`/dev/vdb` is not stable across reboots). This boundary is documented in [README.md](README.md) and the variable descriptions; preserve it when adding related features.

## Conventions

- Provider versions are pinned with `~>` in [main.tf](main.tf) (`openstack ~> 3.4`, `talos ~> 0.10`).
- Resource naming: `${var.cluster_name}-...` everywhere user-visible.
- Conventional Commits (see `git log`): `feat:`, `fix:`, `docs:`, `chore:`, with optional scope like `feat(ci):`.
