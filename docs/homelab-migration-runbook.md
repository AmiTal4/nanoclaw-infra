# NanoClaw: OCI → Homelab Migration Runbook

Goal: move this exact install (all agents, tasks, wirings, memory, credentials, channel
sessions) from the OCI Always Free instance (provisioned by `nanoclaw-infra`) to a homelab
box, with zero reconfiguration. This is a lift-and-shift of state + a rebuild of all
architecture-specific artifacts.

Current host: OCI `VM.Standard.A1.Flex`, **aarch64**, Ubuntu, user `ubuntu`,
install at `/home/ubuntu/nanoclaw-v2`, install slug `2a38bd3e`.
Target host: homelab, **x86_64 Ubuntu Server**. Transfer channel: **Tailscale** (decided).

---

## Hard invariants — read before doing anything

1. **Keep the exact path `/home/ubuntu/nanoclaw-v2` on the homelab** (i.e. a user whose
   home is `/home/ubuntu`; create a `ubuntu` user if needed). The install slug is
   `sha1(projectRoot)[:8]` (`src/install-slug.ts`) and everything hangs off it:
   - systemd unit name `nanoclaw-v2-2a38bd3e`
   - docker image base `nanoclaw-agent-v2-2a38bd3e`
   - the `image_tag` values stored in `container_configs` rows
   Additionally, `container_configs.additional_mounts` stores **absolute host paths**
   (`/home/ubuntu/.gmail-mcp`, `/home/ubuntu/.nanoclaw-aws/liadi`, ...). Same path = zero
   DB edits.
2. **Never run both hosts simultaneously.** WhatsApp (Baileys) allows one active linked
   session — two hosts sharing `store/auth` will fight and can corrupt the session
   (re-linking risks the tctoken/reachout-timelock mess again). Telegram would
   double-poll, Slack would double-answer. Stop OCI services before starting homelab ones.
3. **Rebuild, don't copy, anything architecture-specific** (OCI is ARM; homelab is
   x86_64): `node_modules/`, `dist/`, all docker images, the `onecli` binary,
   the AWS CLI. Exclude `node_modules` and `dist` from rsync.
4. **OneCLI's Postgres volume must move via `pg_dumpall`, not a volume tar** — Postgres
   data directories are not portable across CPU architectures. The `onecli_app-data`
   volume (plain files) can be tar-copied.

---

## Inventory — everything that must move

### The install itself
| What | Path | Notes |
|---|---|---|
| Fork checkout | `/home/ubuntu/nanoclaw-v2` | Custom scripts (`refresh-aws-tokens.sh`, `refresh-github-app-tokens.py`), skills, everything. Exclude `node_modules/`, `dist/`, `logs/` (optional). |
| Central DB + runtime state | `data/` (~865 MB) | `v2.db` (+`-wal`/`-shm` — copy only after service stop), `v2-sessions/`, `attachments/`, `install-id`, `telegram-pairings.json`, `circuit-breaker.json`, `store/`, `env`, `secrets/` |
| **WhatsApp Baileys auth** | `store/auth/` (repo root) | `creds.json`, app-state sync keys, device lists. Preserving this keeps the linked device — no QR re-link, no timelock re-trigger. |
| Per-group workspaces | `groups/` (~2 GB) | Agent memory, CLAUDE.md, skills |
| Env | `.env` (+ `.env.bak*`) | Telegram/Slack tokens, ONECLI_URL/API_KEY, WEBHOOK_PUBLIC_URL, TZ |

### Host-level state outside the repo
| What | Path | Notes |
|---|---|---|
| OneCLI config + creds | `~/.onecli/` | `config.json`, `credentials/api-key`, `docker-compose.yml`, `skills/`, `ca-bundle.pem` |
| OneCLI vault data | docker volumes `onecli_pgdata`, `onecli_app-data` | pgdata via `pg_dumpall`; app-data via tar |
| Cloudflare tunnel | `~/.cloudflared/` + `/etc/cloudflared/config.yml` + system `cloudflared.service` | Tunnel `34ee5cca…` → `webhook.edna-ai.online` → `localhost:3000`. Outbound-only, works behind homelab NAT, **no DNS change needed** — just move creds and run the same tunnel. |
| AWS short-lived-creds source | `~/.nanoclaw-aws/` | `credentials` + `liadi/` (mounted read-only into Liadi's container) |
| GitHub App keys | `~/.nanoclaw-github-apps/` | `moshe.{json,pem}`, `haimdevai.{json,pem}` — used by the 45-min token refresher |
| Google MCP OAuth stores | `~/.gmail-mcp/`, `~/.calendar-mcp/`, `~/.gworkspace-mcp/` | Mounted into Edna's container per `additional_mounts` |
| systemd user units | `~/.config/systemd/user/` | `nanoclaw-v2-2a38bd3e.service`, `nanoclaw-aws-tokens.{service,timer}`, `nanoclaw-github-tokens.{service,timer}` (+ their `wants` symlinks — re-enable instead of copying symlinks) |
| Claude Code state (optional) | `~/.claude/` | Project memory / settings if you'll keep developing from the homelab |

### Rebuilt on the homelab (not copied)
- `pnpm install` + `pnpm run build` (host)
- `./container/build.sh` → `nanoclaw-agent-v2-2a38bd3e:latest`
- Per-group images for the 4 groups with a stored `image_tag` (self-mod installed
  packages): **Edna** `ag-1781724069056-npjd5z`, **shopping** `ag-1781873701698-e67s9w`,
  **Liadi** `36c7d49a-…`, **Haim** `ba7765d8-…`. Rebuild with
  `ncl groups restart --id <id> --rebuild` after the base image exists — spawn does
  `imageTag || latest` and will fail on a missing tag otherwise.
- `onecli` CLI binary (x86_64 build) at `~/.local/bin/onecli`; gateway containers pull
  multi-arch from ghcr via the compose file.
- AWS CLI at `~/.local/bin/aws` (used by `refresh-aws-tokens.sh`).

---

## Phase 0 — Homelab prerequisites

- Linux with systemd; user `ubuntu` with home `/home/ubuntu`;
  `sudo loginctl enable-linger ubuntu` (user services must survive logout).
- Docker Engine + compose plugin; `ubuntu` in the `docker` group.
- Node 22 at `/usr/bin/node` (the unit hardcodes it — either install via distro/NodeSource
  so it lands there, or symlink, or edit the unit), pnpm, `tsx` comes via pnpm.
- python3 (github token refresher), `cloudflared` package.
- Disk: ≥ 30 GB free (repo+data ~3 GB, docker images ~15–20 GB after per-group builds).

## Phase 1 — Transfer channel: Tailscale

OCI has no inbound ports (bastion-only) but unrestricted outbound, so Tailscale works
from both sides and also gives you a management path to the OCI box until decommission.

```bash
# On both boxes
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # authenticate each in the browser, same tailnet

# Verify from OCI
tailscale status
ssh ubuntu@<homelab-tailscale-name-or-100.x-ip> true
```

All rsync commands below use the homelab's Tailscale hostname/IP as `$HOMELAB`.

## Phase 2 — Warm pre-sync (service still running)

Get the bulk of the 3 GB across while live; cutover then only ships a small delta.

```bash
# From the OCI box (adjust HOMELAB)
HOMELAB=ubuntu@homelab
rsync -avz --exclude node_modules --exclude dist --exclude logs \
  /home/ubuntu/nanoclaw-v2/ $HOMELAB:/home/ubuntu/nanoclaw-v2/
rsync -avz ~/.onecli ~/.cloudflared ~/.nanoclaw-aws ~/.nanoclaw-github-apps \
  ~/.gmail-mcp ~/.calendar-mcp ~/.gworkspace-mcp ~/.config/systemd \
  $HOMELAB:/home/ubuntu/
```

(`v2.db` copied while hot is only a placeholder — the authoritative copy happens in
Phase 3 after the service stops.)

## Phase 3 — Cutover (OCI side)

```bash
# 1. Stop everything that writes state or answers messages
systemctl --user stop nanoclaw-v2-2a38bd3e nanoclaw-aws-tokens.timer nanoclaw-github-tokens.timer
sudo systemctl stop cloudflared            # Slack webhooks stop arriving here
docker ps --format '{{.Names}}' | grep -v onecli   # verify no agent containers left

# 2. Dump the OneCLI vault DB (arch-safe)
docker exec onecli-postgres-1 pg_dumpall -U onecli > /home/ubuntu/onecli-vault.sql
docker run --rm -v onecli_app-data:/from -v /home/ubuntu:/to alpine \
  tar czf /to/onecli-app-data.tgz -C /from .

# 3. Final delta sync (now includes a clean v2.db; WAL checkpointed on close)
rsync -avz --delete --exclude node_modules --exclude dist --exclude logs \
  /home/ubuntu/nanoclaw-v2/ $HOMELAB:/home/ubuntu/nanoclaw-v2/
rsync -avz ~/.onecli ~/.cloudflared ~/.nanoclaw-aws ~/.nanoclaw-github-apps \
  ~/.gmail-mcp ~/.calendar-mcp ~/.gworkspace-mcp ~/.config/systemd \
  /home/ubuntu/onecli-vault.sql /home/ubuntu/onecli-app-data.tgz \
  $HOMELAB:/home/ubuntu/
scp /etc/cloudflared/config.yml $HOMELAB:/home/ubuntu/cloudflared-config.yml

# 4. Make sure OCI can't come back by accident
systemctl --user disable nanoclaw-v2-2a38bd3e nanoclaw-aws-tokens.timer nanoclaw-github-tokens.timer
sudo systemctl disable cloudflared
```

## Phase 4 — Bring up on the homelab

```bash
cd /home/ubuntu/nanoclaw-v2

# 1. Host build (x86_64)
pnpm install --frozen-lockfile
pnpm run build

# 2. OneCLI gateway: fresh volumes, restore dump
cd ~/.onecli && docker compose up -d postgres
sleep 10 && docker exec -i onecli-postgres-1 psql -U onecli -d postgres < ~/onecli-vault.sql
docker run --rm -v onecli_app-data:/to -v /home/ubuntu:/from alpine \
  tar xzf /from/onecli-app-data.tgz -C /to
docker compose up -d
# install the x86_64 onecli CLI to ~/.local/bin/onecli, then: onecli agents list

# 3. Cloudflare tunnel (same tunnel ID — DNS untouched)
sudo mkdir -p /etc/cloudflared && sudo cp ~/cloudflared-config.yml /etc/cloudflared/config.yml
sudo cloudflared service install   # or copy the unit; creds already at ~/.cloudflared
sudo systemctl enable --now cloudflared

# 4. Container images
cd /home/ubuntu/nanoclaw-v2 && ./container/build.sh   # base :latest

# 5. Services + timers
systemctl --user daemon-reload
systemctl --user enable --now nanoclaw-v2-2a38bd3e
systemctl --user enable --now nanoclaw-aws-tokens.timer nanoclaw-github-tokens.timer

# 6. Per-group images (host must be running — ncl talks to it over data/cli.sock)
for g in ag-1781724069056-npjd5z ag-1781873701698-e67s9w \
         36c7d49a-3173-45fe-95e8-9947a37e64f7 ba7765d8-5a8b-4715-b4e8-9b6a3218fad5; do
  ncl groups restart --id "$g" --rebuild
done
```

## Phase 5 — Verify

- `tail -f logs/nanoclaw.error.log` — no crash-loop / circuit-breaker entries
  (delete `data/circuit-breaker.json` if it trips from pre-migration state).
- Telegram DM Edna → reply arrives (long-poll, no inbound needed).
- WhatsApp DM → reply arrives (Baileys reconnects with copied creds; watch log for
  a successful WS open, no `logged out` event).
- Slack: `curl -s https://webhook.edna-ai.online/` resolves through the tunnel;
  message a Slack agent → reply.
- `ncl sessions list`, `ncl tasks list` — tasks intact; wait for the next scheduled
  task to fire.
- `onecli agents list` + one credentialed action per critical integration
  (Gmail, GitHub, AWS for Liadi — check the two timers ran: `systemctl --user list-timers`).

## Rollback

The OCI box stays intact (services disabled, data untouched) until verification passes.
To roll back: stop everything on the homelab, re-enable + start the three user units and
`cloudflared` on OCI. Nothing on OCI was deleted during migration. If the homelab ran for
a while first, `data/` and the vault have diverged — rsync them back before restarting.

## Decommission (after a comfortable soak, e.g. 1–2 weeks)

From the `nanoclaw-infra` clone on your workstation:
```bash
terraform -chdir=infra destroy
```
Take a final tarball of `/home/ubuntu/{nanoclaw-v2,.onecli,.cloudflared,.nanoclaw-*,.g*-mcp}`
and the vault SQL dump before destroying — it's the last copy of the WhatsApp session and
OAuth grants.

## Known gaps / decisions to make

- **`/usr/bin/node`** — unit hardcodes it; ensure Node 22 resolves there or patch the unit.
- **Backups** — homelab loses OCI's implicit "it's in the cloud" durability; consider a
  cron'd `v2.db` + vault dump backup off-box once migrated.
