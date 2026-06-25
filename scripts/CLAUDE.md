# Scripts

Reusable diagnostic scripts and issue documentation created during NanoClaw troubleshooting sessions.

## Structure

| Path | Purpose |
|------|---------|
| `proxy-command.sh` | ProxyCommand backend for sshm/ssh — called by SSH automatically, not directly |
| `whatsapp-diagnostics/` | WhatsApp Baileys connection issues — timelock checks, token debugging |

Connection management is handled by Claude skills — see `.claude/commands/` in the repo root:

| Skill | Purpose |
|-------|---------|
| `/connect` | Create an OCI Bastion session and open SSH with SOCKS5 proxy |
| `/setup-sshm` | Register the instance in `~/.ssh/config` for sshm/ssh (run once) |

---

## connect.sh — Bastion SSH + SOCKS5 proxy

The instance has **no open inbound ports**. All remote access goes through [OCI Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/Concepts/bastionoverview.htm), which creates short-lived managed-SSH sessions (max 3 hours) tunnelled through OCI's internal network.

`connect.sh` reads all infrastructure values (`bastion_id`, `instance_id`, `region`) from `terraform output` at runtime — there are no hardcoded OCIDs in the script.

### Prerequisites

- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with profile `pa`
- `terraform apply` has been run at least once (state must exist)
- SSH key pair at `~/.ssh/id_rsa` / `~/.ssh/id_rsa.pub` (override via env vars)

### Usage

Run from the repo root:

```bash
./scripts/connect.sh
```

### SOCKS5 proxy

While connected, a SOCKS5 dynamic proxy is open on `localhost:1080`. This tunnels **all remote ports** without needing to list them individually:

```bash
# onecli (runs on remote :10254)
ALL_PROXY=socks5://localhost:1080 onecli ...

# curl
curl --proxy socks5://localhost:1080 http://localhost:10254/

# browser — set SOCKS5 proxy to localhost:1080
```

### Overrides

All defaults can be overridden via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | `~/.ssh/id_rsa.pub` | Path to SSH public key |
| `SSH_PRIVATE_KEY` | `~/.ssh/id_rsa` | Path to SSH private key |
| `SOCKS5_PORT` | `1080` | Local SOCKS5 proxy port |
| `OS_USER` | `ubuntu` | Remote OS username |
| `TF_DIR` | repo root | Path to Terraform root directory |

```bash
SSH_PRIVATE_KEY=~/.ssh/my_key SOCKS5_PORT=9050 ./scripts/connect.sh
```

---

## setup-sshm.sh — sshm / ssh config integration

Run once after `terraform apply` to register the instance in `~/.ssh/config`:

```bash
./scripts/setup-sshm.sh
```

This adds a `Host pa` block pointing to `proxy-command.sh` as the `ProxyCommand`, so both `sshm` and plain `ssh` work without any extra steps:

```bash
sshm pa   # or: ssh pa
```

Each connection transparently creates a fresh OCI Bastion port-forwarding session (~30s), then tunnels SSH through it. The SOCKS5 proxy on `localhost:1080` stays active for the duration of the session.

Re-run `setup-sshm.sh` if the instance private IP changes (e.g. after `terraform destroy` + `apply`).

### proxy-command.sh

Called by SSH automatically via `ProxyCommand` — not meant to be invoked directly. Creates a port-forwarding session, waits for ACTIVE, extracts the bastion endpoint from OCI's SSH metadata, and pipes stdin/stdout through `ssh -W`.

---

## Diagnostic scripts (TypeScript)

Scripts are written in TypeScript and run via `pnpm exec tsx` from the NanoClaw project root (`/home/ubuntu/nanoclaw-v2`):

```bash
cd /home/ubuntu/nanoclaw-v2
pnpm exec tsx /home/ubuntu/scripts/whatsapp-diagnostics/check-timelock.ts
```

Each subdirectory has a `README.md` documenting the issue, root cause, and fix for future reference.
