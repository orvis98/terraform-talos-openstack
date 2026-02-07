// A generated module for TerraformTalosOpenstack functions
//
// This module provides CI/CD functions for the Terraform Talos OpenStack module.

package main

import (
	"context"
	"dagger/terraform-talos-openstack/internal/dagger"
)

type TerraformTalosOpenstack struct{}

// Lint runs Terraform formatting check and validation
//
// Example usage: dagger call lint --source .
func (m *TerraformTalosOpenstack) Lint(
	ctx context.Context,
	// Source directory containing Terraform files
	// +defaultPath="/"
	source *dagger.Directory,
) (string, error) {
	// Use the official Terraform container
	container := dag.Container().
		From("hashicorp/terraform:1.10").
		WithDirectory("/src", source).
		WithWorkdir("/src")

	// Run terraform fmt -check to verify formatting
	fmtOutput, err := container.
		WithExec([]string{"fmt", "-check", "-recursive"},
			dagger.ContainerWithExecOpts{UseEntrypoint: true}).
		Stdout(ctx)
	if err != nil {
		return "", err
	}

	// Run terraform init (required for validation)
	container = container.
		WithExec([]string{"init", "-backend=false"},
			dagger.ContainerWithExecOpts{UseEntrypoint: true})

	// Run terraform validate
	validateOutput, err := container.
		WithExec([]string{"validate"},
			dagger.ContainerWithExecOpts{UseEntrypoint: true}).
		Stdout(ctx)
	if err != nil {
		return "", err
	}

	return "Formatting check:\n" + fmtOutput + "\nValidation:\n" + validateOutput, nil
}
