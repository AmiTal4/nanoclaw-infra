# PA Infrastructure

OCI Always Free Ubuntu instance running [NanoClaw](https://github.com/nanocoai/nanoclaw), managed via Terraform and accessed through Claude Code skills.

- No inbound ports open from the internet — all SSH access goes through [OCI Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/Concepts/bastionoverview.htm)
- SOCKS5 dynamic proxy tunnels all remote ports while connected
- Claude skills handle setup, deployment, and connection end-to-end

## Getting started

**Windows (PowerShell):**
```powershell
.\run.ps1
```

**Linux / macOS / Git Bash:**
```bash
./run.sh
```

This checks that Claude Code is installed (and installs it via npm if not), then launches it. From there, Claude escorts you through everything:

| Skill | What it does |
|-------|-------------|
| `/install` | Validates and installs all prerequisites — Terraform, OCI CLI, SSH keys, OCI profile, tfvars |
| `/deploy` | Provisions the infrastructure: `terraform init → plan → apply` |
| `/setup-instance` | Installs Git and clones NanoClaw on the remote instance via Bastion |
| `/setup-sshm` | Registers the instance in `~/.ssh/config` so `sshm pa` / `ssh pa` work |
| `/connect` | Creates an OCI Bastion session and hands you the SSH command to run |

**Typical first-time flow:**
```
/install → /deploy → /setup-instance → /setup-sshm
```

Then connect any time with `/connect` or `sshm pa`.

---

## Connecting & port tunneling

All SSH access goes through OCI Bastion — no ports are open on the instance. Each session is time-limited (max 3 hours) and created on demand.

While connected, a SOCKS5 proxy is open on `localhost:1080`, tunnelling all remote ports:

```bash
# onecli (runs on remote :10254)
ALL_PROXY=socks5://localhost:1080 onecli ...

# curl
curl --proxy socks5://localhost:1080 http://localhost:10254/

# browser — set SOCKS5 proxy to localhost:1080
```

---

## Always Free shape notes

- `VM.Standard.A1.Flex` (default): Ampere ARM, up to 4 OCPUs / 24 GB RAM total. Adjust in `infra/terraform.tfvars`.
  Capacity is occasionally constrained — if apply fails with "Out of host capacity", retry later or switch to `VM.Standard.E2.1.Micro`.
- `VM.Standard.E2.1.Micro`: AMD, 1 OCPU / 1 GB RAM. Up to 2 instances Always Free.
- Boot volume defaults to 50 GB; Always Free covers up to 200 GB across up to 2 boot volumes.

## Security

No inbound traffic is permitted from the internet. SSH (TCP/22) is only allowed from within the VCN CIDR so OCI Bastion can reach the instance via its private IP. Outbound traffic is unrestricted.

## Known Issues

### WhatsApp DM sending silently fails (Baileys reachout timelock)

Outgoing WhatsApp DMs can appear delivered in logs but never reach the recipient. Root cause: Baileys rc.9 omits required privacy tokens (`tctoken`/`cstoken`), causing WhatsApp to impose a server-side reachout timelock (`RESTRICT_ALL_COMPANIONS`) that silently drops outgoing DMs from linked devices.

**Fix**: upgrade `@whiskeysockets/baileys` to rc13+. See [`scripts/whatsapp-diagnostics/README.md`](scripts/whatsapp-diagnostics/README.md) for a full breakdown and diagnostic scripts.

## Cleanup

Ask Claude to run `terraform -chdir=infra destroy`, or run it directly.

## File layout

| Path | Purpose |
|------|---------|
| `run.sh` / `run.ps1` | Entry point — installs Claude Code if needed, then launches it |
| `CLAUDE.md` | Project context loaded by Claude on startup |
| `infra/` | Terraform configuration (providers, network, compute, bastion) |
| `infra/terraform.tfvars.example` | Copy to `infra/terraform.tfvars` and fill in your values |
| `scripts/proxy-command.sh` | SSH ProxyCommand backend used by `sshm pa` / `ssh pa` |
| `.claude/commands/` | Claude skills — `/install`, `/deploy`, `/connect`, `/setup-sshm` |
