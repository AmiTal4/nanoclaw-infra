# Tailscale on the PA instance

Puts the OCI instance on the same tailnet as the homelab, so homelab monitoring
and automations can reach NanoClaw and vice versa — without opening a single
inbound port on the VCN.

This is an interim arrangement. NanoClaw moves to the homelab later in 2026
(see [`homelab-migration-runbook.md`](homelab-migration-runbook.md), which uses
this same tailnet as its transfer channel). Setup is therefore deliberately
manual and one-time — there is no Terraform resource and no Vault-stored auth
key. **A `terraform destroy` / rebuild loses the tailnet membership and you
redo Step 2 below.**

## Why this doesn't weaken the "zero open ports" design

Tailscale is outbound-only: WireGuard over UDP 41641, falling back to a DERP
relay over 443 when UDP is blocked. The VCN security lists stay egress-only and
unchanged. The OCI Bastion remains the primary management path; Tailscale is a
second, independently-authenticated one.

It *is* a second inbound path, though, which is why the node is tagged and
default-denied in the ACL rather than left in the allow-all default.

## Step 1 — ACL

Paste [`tailscale-acl.hujson`](tailscale-acl.hujson) into
<https://login.tailscale.com/admin/acls/file>, substituting your homelab's
`100.x` address for `HOMELAB_TAILSCALE_IP`. Do this **before** Step 2 — the
`tag:cloud` tag must exist in `tagOwners` or the node cannot claim it.

## Step 2 — Install and join

```bash
# Signed apt repo -- not the piped install.sh
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
sudo apt-get update && sudo apt-get install -y tailscale

sudo tailscale up \
  --hostname=pa-oci \
  --advertise-tags=tag:cloud \
  --accept-dns=false \
  --accept-routes=false
```

Open the printed URL to authenticate. Then, in the admin console, **disable key
expiry** on the `pa-oci` node — the default 180-day expiry would silently drop a
headless box off the tailnet.

### Why those flags

| Flag | Reason |
|---|---|
| `--accept-dns=false` | The box would otherwise take its DNS from the tailnet's AdGuard server. That makes NanoClaw's DNS depend on the homelab being up — a bad failure mode for a headless cloud box. Reach homelab services by tailnet IP instead. |
| `--accept-routes=false` | No need for homelab subnet routes; keeps the cloud box's routing table predictable. |
| `--advertise-tags=tag:cloud` | Binds the node to the ACL rules above and makes it tag-owned, so it survives user key expiry. |
| *(no `--advertise-exit-node`)* | The cloud box is not an exit node, and is not granted `autogroup:internet`, so it cannot use the homelab as one either. |

## Docker / NanoClaw containers

NanoClaw agents run in containers. Two things to know:

- **Container → tailnet IPs works.** Verified: a container on a user-defined
  bridge network reached a homelab service over its `100.x` address, and was
  correctly blocked on a port the ACL denies. The host holds the
  `100.64.0.0/10` route via `tailscale0` and `net.ipv4.ip_forward` is already
  `1`. No extra config — and note the ACL applies to container traffic too,
  since it egresses via the host's Tailscale node.
- **MagicDNS names do not resolve in containers.** Containers on a user-defined
  network get Docker's embedded resolver (`127.0.0.11`), which forwards to the
  host's upstream — and the host's `/etc/resolv.conf` is the systemd-resolved
  stub (`127.0.0.53`), which Docker discards in favour of a public resolver.
  Either way the tailnet resolver is never consulted. Since we run
  `--accept-dns=false` this is moot — **address homelab services by their
  `100.x` IP**, not by MagicDNS name.

If you later decide you want MagicDNS/AdGuard inside containers, you need both:
`tailscale set --accept-dns=true`, *and* `--dns=<adguard-tailnet-ip>` on the
containers — plus an AdGuard upstream rule forwarding `ts.net` to
`100.100.100.100`, or `*.ts.net` lookups return NXDOMAIN.

## Verify

```bash
tailscale status
tailscale ip -4

# Confirm the node is tagged, online, and has no key expiry
tailscale status --json | python3 -c \
  'import sys,json; s=json.load(sys.stdin)["Self"]; print(s["HostName"], s.get("Tags"), s.get("KeyExpiry"))'
```

Confirm the ACL is actually restricting — an allowed port should connect and a
denied one should not:

```bash
for p in 53 8123 22; do
  timeout 5 bash -c "echo > /dev/tcp/<homelab-tailscale-ip>/$p" 2>/dev/null \
    && echo "$p open" || echo "$p blocked"
done
```

`22` blocking while `8123` connects is the signal the ACL took effect. A port
that is allowed by the ACL but has nothing listening also shows as blocked, so
don't read a single closed port as an ACL failure.

From a homelab or laptop on the tailnet:

```bash
ssh ubuntu@<pa-oci-tailscale-ip>    # uses ~/.ssh/id_rsa_oci
```

## Relationship to the Bastion tunnel

`/connect` and `ssh pa-cmd` are unchanged and remain the primary path. Tailscale
gives you a fallback that does not expire the way Bastion sessions do — useful
when the SOCKS5 tunnel drops (`errno=10061`) and you need to get in to fix it.
