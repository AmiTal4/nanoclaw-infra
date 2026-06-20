# PA — OCI Always Free Ubuntu Instance (Terraform)

Terraform configuration that provisions a single Always Free-eligible
Ubuntu compute instance on Oracle Cloud Infrastructure (OCI) with:

- A dedicated VCN, public subnet, internet gateway, and route table (full internet access)
- A public IP address attached to the instance
- A security list that allows **inbound SSH (TCP/22) only** - all other ingress is blocked, egress is unrestricted
- The latest available Canonical Ubuntu image for the chosen shape (auto-detected via a data source, no hardcoded image OCID)

## Prerequisites

1. An OCI account with Always Free resources available in your home region.
2. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
3. An OCI API signing key pair, with the public key uploaded to your OCI user
   (Identity & Security -> Users -> your user -> API Keys -> Add API Key).
   This gives you the `tenancy_ocid`, `user_ocid`, `fingerprint`, and `private_key_path` values.
4. A local SSH key pair (e.g. `ssh-keygen -t ed25519`) - the public key is
   injected into the instance for the `ubuntu` user.

## Setup

1. Copy the example variables file and fill in your own values:

   ```
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your tenancy/user OCIDs, API key fingerprint,
   compartment OCID, region, and SSH key path. Strongly consider setting
   `ssh_allowed_cidr` to your own public IP (`a.b.c.d/32`) instead of
   leaving SSH open to the world.

3. Initialize and apply:

   ```
   terraform init
   terraform plan
   terraform apply
   ```

4. Connect once it's up:

   ```
   terraform output ssh_command
   ```

## After provisioning — install NanoClaw

Once the instance is up, connect to it and install [NanoClaw](https://github.com/nanocoai/nanoclaw):

1. **SSH into the instance** using the key you provided:

   ```
   terraform output ssh_command
   ```

   Copy and run the printed command (or use your own SSH client with the same key).

2. **Install Git:**

   ```bash
   sudo apt-get update && sudo apt-get install -y git
   ```

3. **Install NanoClaw** by following the quickstart in the [NanoClaw repo](https://github.com/nanocoai/nanoclaw).

---

## Always Free shape notes

- `VM.Standard.E2.1.Micro` (default): AMD, 1 OCPU / 1 GB RAM, fixed shape. Up to 2 instances are Always Free.
- `VM.Standard.A1.Flex`: Ampere ARM, flexible. Up to 4 OCPUs / 24 GB RAM total across instances are Always Free. Set `instance_shape = "VM.Standard.A1.Flex"` and adjust `instance_ocpus` / `instance_memory_in_gbs`.
  Capacity for A1.Flex is occasionally constrained in busy regions - if `terraform apply` fails with an "Out of host capacity" error, retry later or switch to `VM.Standard.E2.1.Micro`.
- Boot volume defaults to 50 GB; Always Free covers up to 200 GB across up to 2 boot volumes.

## Security

The security list only opens TCP/22 (SSH) for `ssh_allowed_cidr`. No other
ports are reachable from the internet. Outbound traffic is unrestricted so
the instance can reach the internet for package updates, etc.

## Cleanup

```
terraform destroy
```

## File layout

| File | Purpose |
|---|---|
| `versions.tf` | Terraform/provider version constraints and `oci` provider config |
| `variables.tf` | All input variables |
| `data.tf` | Availability domain + latest Ubuntu image lookups |
| `network.tf` | VCN, subnet, internet gateway, route table, security list |
| `compute.tf` | The compute instance itself |
| `outputs.tf` | Public IP, instance OCID, ready-to-use SSH command |
| `terraform.tfvars.example` | Template for your own `terraform.tfvars` (not committed) |
