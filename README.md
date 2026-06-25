# OCI Always Free Ubuntu Instance (Terraform)

Terraform configuration that provisions a single Always Free-eligible
Ubuntu compute instance on Oracle Cloud Infrastructure (OCI) with:

- A dedicated VCN, public subnet, internet gateway, and route table
- A public IP address for outbound internet access (apt updates, etc.) — **no inbound ports are open from the internet**
- An [OCI Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/Concepts/bastionoverview.htm) for secure, zero-open-port SSH access
- The latest available Canonical Ubuntu image for the chosen shape (auto-detected, no hardcoded image OCID)

## Prerequisites

1. An OCI account with Always Free resources available in your home region.
2. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
3. [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) — needed both for Terraform auth and for `scripts/connect.sh`. Run `oci setup config` and use profile name `pa`.
4. A local SSH key pair (e.g. `ssh-keygen -t ed25519`) — the public key is injected into the instance for the `ubuntu` user.

## Setup

1. Copy the example variables file and fill in your own values:

   ```
   cp infra/terraform.tfvars.example infra/terraform.tfvars
   ```

2. Edit `infra/terraform.tfvars` with your tenancy/compartment OCIDs and region. See `infra/variables.tf` for all available options.

3. Initialize and apply (all commands use `-chdir=infra`):

   ```
   terraform -chdir=infra init
   terraform -chdir=infra plan
   terraform -chdir=infra apply
   ```

4. Connect once it's up using the Claude skill:

   ```
   /connect
   ```

   This creates a short-lived OCI Bastion session and opens an SSH connection with a SOCKS5 proxy — see [Connecting & port tunneling](#connecting--port-tunneling) below.

## After provisioning — install NanoClaw

Once the instance is up, connect and install [NanoClaw](https://github.com/nanocoai/nanoclaw):

1. **Open a session:**

   ```
   /connect
   ```

2. **Install Git:**

   ```bash
   sudo apt-get update && sudo apt-get install -y git
   ```

3. **Install NanoClaw** by following the quickstart in the [NanoClaw repo](https://github.com/nanocoai/nanoclaw).

---

## Connecting & port tunneling

The instance has **no open inbound ports**. All access goes through the OCI Bastion service, which creates managed-SSH sessions (max 3 hours) tunnelled through OCI's internal network. The `scripts/connect.sh` script handles the full flow automatically.

### SOCKS5 dynamic proxy

While connected, a SOCKS5 proxy is open on `localhost:1080`. This tunnels **all remote ports** — no need to list them individually:

```bash
# onecli (runs on remote :10254)
ALL_PROXY=socks5://localhost:1080 onecli ...

# curl
curl --proxy socks5://localhost:1080 http://localhost:10254/

# browser — configure SOCKS5 proxy to localhost:1080
```

Override the local port:

```bash
SOCKS5_PORT=9050 ./scripts/connect.sh
```

See [`scripts/CLAUDE.md`](scripts/CLAUDE.md) for full documentation and all available overrides.

---

## Always Free shape notes

- `VM.Standard.E2.1.Micro`: AMD, 1 OCPU / 1 GB RAM, fixed shape. Up to 2 instances are Always Free.
- `VM.Standard.A1.Flex` (default): Ampere ARM, flexible. Up to 4 OCPUs / 24 GB RAM total across instances are Always Free. Adjust `instance_ocpus` / `instance_memory_in_gbs` in `terraform.tfvars`.
  Capacity is occasionally constrained in busy regions — if `terraform apply` fails with "Out of host capacity", retry later or switch to `VM.Standard.E2.1.Micro`.
- Boot volume defaults to 50 GB; Always Free covers up to 200 GB across up to 2 boot volumes.

## Security

The security list allows **no inbound traffic from the internet**. SSH (TCP/22) is only permitted from within the VCN CIDR, so the OCI Bastion can reach the instance via its private IP while remaining completely unreachable from outside. Outbound traffic is unrestricted.

## Known Issues

### WhatsApp DM sending silently fails (Baileys reachout timelock)

When running NanoClaw with an outdated Baileys version, outgoing WhatsApp DMs can appear delivered in the logs but never reach the recipient. The root cause is that Baileys rc.9 omits required privacy tokens (`tctoken`/`cstoken`) from outgoing messages, which causes WhatsApp to impose a server-side reachout timelock (`RESTRICT_ALL_COMPANIONS`) that silently drops all outgoing DMs from linked devices.

**Fix**: upgrade `@whiskeysockets/baileys` to rc13+. See [`scripts/whatsapp-diagnostics/README.md`](scripts/whatsapp-diagnostics/README.md) for a full breakdown of the root cause, the fix, and diagnostic scripts for checking timelock status.

## Cleanup

```
terraform destroy
```

## File layout

| Path | Purpose |
|------|---------|
| `start.sh` / `start.ps1` | Entry point — installs Claude Code if needed, then launches it |
| `infra/versions.tf` | Terraform/provider version constraints and `oci` provider config |
| `infra/variables.tf` | All input variables |
| `infra/data.tf` | Availability domain + latest Ubuntu image lookups |
| `infra/network.tf` | VCN, subnet, internet gateway, route table, security list |
| `infra/compute.tf` | Compute instance with OCA Bastion plugin enabled |
| `infra/bastion.tf` | OCI Bastion resource |
| `infra/outputs.tf` | Instance OCID, private IP, bastion OCID, region |
| `infra/terraform.tfvars.example` | Template for your own `terraform.tfvars` (not committed) |
| `scripts/proxy-command.sh` | ProxyCommand backend for sshm/ssh via OCI Bastion |
| `.claude/commands/install.md` | `/install` skill — validate and install all prerequisites |
| `.claude/commands/deploy.md` | `/deploy` skill — terraform init → plan → apply |
| `.claude/commands/connect.md` | `/connect` skill — create a Bastion session and SSH in |
| `.claude/commands/setup-sshm.md` | `/setup-sshm` skill — register instance in `~/.ssh/config` |
