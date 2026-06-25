# PA Infrastructure

This repo provisions and manages an OCI Always Free Ubuntu instance that runs [NanoClaw](https://github.com/nanocoai/nanoclaw) — a personal AI assistant.

## What's deployed

- OCI compute instance (ARM A1.Flex, Ubuntu) in `il-jerusalem-1`
- VCN with internet access outbound-only — no inbound ports open from the internet
- OCI Bastion for secure SSH access (zero open ports)
- All access via Claude skills below

## Key facts

- OCI CLI profile: `pa` (auth type: `api_key` — permanent, no re-authentication needed)
- Instance private IP: read from `terraform output -raw instance_private_ip`
- Instance OS user: `ubuntu`
- SSH keys: `~/.ssh/id_rsa_oci` / `~/.ssh/id_rsa_oci.pub`
- OCI API key: `~/.oci/oci_api_key.pem` (fingerprint in `~/.oci/config`)
- Terraform state is local (`terraform.tfstate`)
- OCI CLI flag required on all calls: `--profile pa`

## Available skills

Guide the user through these in order for a fresh setup:

| Skill | When to use |
|-------|-------------|
| `/install` | First time — validates and installs all prerequisites (Terraform, OCI CLI, SSH keys, OCI profile, tfvars) |
| `/deploy` | After `/install` — runs terraform init → plan → apply |
| `/setup-instance` | After `/deploy` — installs Git and clones NanoClaw on the remote instance via Bastion |
| `/setup-sshm` | After `/deploy` — registers the instance in `~/.ssh/config` for `sshm pa` / `ssh pa` |
| `/connect` | Any time — creates an OCI Bastion session and prints the SSH command to run |

When a user opens Claude Code in this repo for the first time, proactively suggest running `/install` to check their setup.

## Project layout

```
run.sh / run.ps1         Entry point — installs Claude Code if needed, then launches it
CLAUDE.md                    This file — project context for Claude
README.md                    Human-readable setup guide
infra/                       Terraform configuration
  *.tf                       Infrastructure definitions
  terraform.tfvars.example   Copy to terraform.tfvars and fill in your values
  terraform.tfvars           Your local values (gitignored)
scripts/
  proxy-command.sh           SSH ProxyCommand backend for sshm (called by SSH, not directly)
  whatsapp-diagnostics/      NanoClaw WhatsApp debugging scripts
.claude/commands/
  install.md                 /install skill
  deploy.md                  /deploy skill
  connect.md                 /connect skill
  setup-sshm.md              /setup-sshm skill
  setup-instance.md          /setup-instance skill
```

## Common issues

- **OCI auth issues**: auth is now permanent API key (`~/.oci/oci_api_key.pem`). If a command fails with 401, verify the key file exists and the fingerprint in `~/.oci/config` matches
- **"Out of host capacity"**: A1.Flex capacity is occasionally constrained — retry later or switch to `VM.Standard.E2.1.Micro` in `terraform.tfvars`
- **`sshm pa` silently fails**: `terraform` and `oci` must be on PATH in the bash environment that OpenSSH invokes — test with `bash scripts/proxy-command.sh <instance-private-ip> 22`
- **`ssh pa-cmd` not found / hangs**: `pa-cmd` requires an active `pa` connection (SOCKS5 proxy on localhost:1080). Run `/connect` first.
