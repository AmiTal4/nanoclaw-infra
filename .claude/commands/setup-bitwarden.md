Migrate the hardcoded BWS access token off the remote instance and into OCI Vault, then configure the instance to fetch it on demand via Instance Principal auth and inject it into NanoClaw's config DB.

## How it works (read first)

NanoClaw v2 stores per-group container config in a SQLite DB (`data/v2.db`,
`container_configs.mcp_servers`) and **regenerates `groups/<group>/container.json`
from that DB at every spawn** (`materializeContainerJson`). So `container.json` is
a generated artifact — editing it directly is silently overwritten on the next
spawn. The token must be written to the **DB**, which is what this skill does:

- The token lives in OCI Vault (source of truth for rotation).
- `scripts/fetch-bws-token.sh` (deployed to the instance) fetches it via Instance
  Principal and `scripts/inject-bws-token.cjs` writes it into `v2.db`.
- The DB is WAL-mode, so injection is safe while NanoClaw runs; the next browser
  spawn reads the new value — **no restart required**.

## 1. Check SOCKS5 tunnel

The SOCKS5 tunnel (localhost:1080) must be up — it is used to reach the instance via `ssh pa-cmd`.

**Windows** (PowerShell):
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```
**bash / macOS / Linux**:
```bash
nc -z -w1 localhost 1080 && echo open || echo closed
```

If the result is `False` / `closed`, tell the user to run `/connect` first and stop.

## 2. Read the current BWS token from the remote instance

Try the legacy token file first:
```bash
ssh pa-cmd 'cat /home/ubuntu/nanoclaw-v2/data/secrets/bws-browser.token 2>/dev/null'
```

If empty, fall back to the DB (where NanoClaw v2 actually keeps it):
```bash
ssh pa-cmd 'cd /home/ubuntu/nanoclaw-v2 && node -e "
  const Database = require(\"./node_modules/better-sqlite3\");
  const db = new Database(\"./data/v2.db\", {readonly:true});
  const r = db.prepare(\"SELECT mcp_servers FROM container_configs WHERE mcp_servers LIKE ?\").get(\"%BWS_ACCESS_TOKEN%\");
  const j = JSON.parse(r.mcp_servers);
  for (const k of Object.keys(j)) if (j[k].env && j[k].env.BWS_ACCESS_TOKEN) console.log(j[k].env.BWS_ACCESS_TOKEN);
  db.close();
"'
```

Store the token value — you will need it in step 4. If both are empty the token is already migrated; skip to step 5.

## 3. Read the Vault secret OCID from Terraform output

```bash
terraform -chdir=infra output -raw vault_secret_ocid
```

If this fails with "The output variable requested could not be found", the Vault has not been applied yet. Tell the user to run `/deploy` first and stop.

Store the OCID — you will need it in steps 4, 5, and 6.

## 4. Upload the token to OCI Vault

```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
TOKEN="<token from step 2>"
TOKEN_B64=$(printf '%s' "$TOKEN" | base64 -w0 2>/dev/null || printf '%s' "$TOKEN" | base64)
oci vault secret update-base64 \
  --secret-id "$SECRET_OCID" \
  --secret-content-content "$TOKEN_B64" \
  --profile pa --region il-jerusalem-1
```

Wait for OCI to confirm the update (returns JSON with the updated secret metadata).

## 5. Verify Instance Principal access from the remote instance

Prove the instance can fetch its own secret with no local credentials:
```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
ssh pa-cmd "/home/ubuntu/bin/oci secrets secret-bundle get \
  --secret-id \"$SECRET_OCID\" \
  --auth instance_principal \
  --query 'data.\"secret-bundle-content\".content' \
  --raw-output | base64 -d"
```

The output should be the raw token string. If it fails with **404 NotAuthorizedOrNotFound**:
- The Vault IAM policy / dynamic group is applied by `/deploy` (see `infra/vault.tf`).
  Two requirements are baked in there and easy to get wrong: the dynamic group
  matching rule must use `instance.id` (not `resource.id`), and the policy must
  reference the group **domain-qualified** as `'Default'/'pa-instance-group'`.
- Changing a dynamic group matching rule has an **~1 hour** server-side propagation
  delay (Oracle docs); a reboot does not speed it up. If `vault.tf` was just
  applied, wait and retry. If it still fails after ~1h, run `/deploy` and recheck.

Do not proceed until this returns the token.

## 6. Deploy the fetch + inject scripts and write the secret OCID file

The scripts live in the repo under `scripts/`. Deploy them and record the OCID in a
sibling file (kept off the repo — it is environment-specific):
```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
ssh pa-cmd 'mkdir -p /home/ubuntu/scripts'
printf '%s\n' "$SECRET_OCID" | ssh pa-cmd 'cat > /home/ubuntu/scripts/bws-secret.ocid'
tr -d '\r' < scripts/fetch-bws-token.sh | ssh pa-cmd 'cat > /home/ubuntu/scripts/fetch-bws-token.sh && chmod +x /home/ubuntu/scripts/fetch-bws-token.sh'
tr -d '\r' < scripts/inject-bws-token.cjs | ssh pa-cmd 'cat > /home/ubuntu/scripts/inject-bws-token.cjs'
```

## 7. Run the fetch script to inject the token into the DB

```bash
ssh pa-cmd 'bash /home/ubuntu/scripts/fetch-bws-token.sh'
```

Expected output: `Done. Rows updated: <n> | token prefix: ...`. `Rows updated: 0`
means the DB already held the same token (fine). To prove the write path on a fresh
setup, you can set a sentinel first and confirm it is restored — see the round-trip
check in the repo history.

## 8. Delete the legacy plaintext token file (hygiene)

The old setup left the token in plaintext on disk. Vault is now the source of truth:
```bash
ssh pa-cmd 'rm -f /home/ubuntu/nanoclaw-v2/data/secrets/bws-browser.token && echo deleted'
```

(The token still lives in plaintext inside `v2.db` because NanoClaw needs the literal
value at spawn time — truly removing it from disk would require a NanoClaw feature for
command/indirection-based secrets. Vault remains the rotation source of truth.)

## 9. No restart needed

NanoClaw regenerates `container.json` from the DB at the next browser spawn, so the
new token is picked up automatically. To force an immediate refresh you may stop any
running browser container (NanoClaw respawns it on the next message):
```bash
ssh pa-cmd 'docker ps --filter name=browser --format "{{.Names}}" | xargs -r docker stop'
```

## 10. Confirm success

Tell the user:
- The BWS token is stored in OCI Vault (`bws-browser-token`).
- The instance fetches it via Instance Principal and injects it into NanoClaw's DB
  (`v2.db`) — `container.json` is regenerated from the DB, so the file approach is
  not used.
- No restart needed; the next browser spawn picks up the token.
- **To rotate the token:** update it in Vault (repeat step 4 with the new value), then
  re-run `/home/ubuntu/scripts/fetch-bws-token.sh` on the instance. No restart required.
