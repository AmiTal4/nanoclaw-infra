Migrate the hardcoded BWS access token off the remote instance and into OCI Vault, then configure the instance to fetch it on demand via Instance Principal auth.

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

Try the token file first:
```bash
ssh pa-cmd 'cat /home/ubuntu/nanoclaw-v2/data/secrets/bws-browser.token 2>/dev/null'
```

If that returns nothing (file does not exist), fall back to container.json:
```bash
ssh pa-cmd 'jq -r ".mcpServers.bitwarden_secrets.env.BWS_ACCESS_TOKEN" /home/ubuntu/nanoclaw-v2/groups/browser/container.json'
```

Store the token value — you will need it in step 4.

## 3. Read the Vault secret OCID from Terraform output

```bash
terraform -chdir=infra output -raw vault_secret_ocid
```

If this fails with "The output variable requested could not be found", the Vault has not been applied yet. Tell the user to run `/deploy` first and stop.

Store the OCID — you will need it in steps 4, 5, 7, and 8.

## 4. Upload the token to OCI Vault

Base64-encode the token and update the secret:
```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
TOKEN="<token from step 2>"
TOKEN_B64=$(printf '%s' "$TOKEN" | base64 -w0 2>/dev/null || printf '%s' "$TOKEN" | base64)
oci vault secret update-base64 \
  --secret-id "$SECRET_OCID" \
  --secret-content-content "$TOKEN_B64" \
  --profile pa --region il-jerusalem-1
```

Wait for OCI to confirm the update (the command returns JSON with the updated secret metadata).

## 5. Verify Instance Principal access from the remote instance

Run on the remote instance via SOCKS5 to prove it can fetch its own secret without local credentials:
```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
ssh pa-cmd "oci secrets secret-bundle get \
  --secret-id \"$SECRET_OCID\" \
  --auth instance_principal \
  --query 'data.\"secret-bundle-content\".content' \
  --raw-output | base64 -d"
```

The output should be the raw token string. If the command fails with a 401 or "not authorized", the IAM policy or dynamic group has not propagated yet — wait 60 seconds and retry. If it still fails, tell the user to run `/deploy` to apply the Vault policy and stop.

## 6. Remove the hardcoded token from container.json

```bash
ssh pa-cmd 'cd /home/ubuntu/nanoclaw-v2 && \
  jq "del(.mcpServers.bitwarden_secrets.env.BWS_ACCESS_TOKEN)" \
  groups/browser/container.json > /tmp/container.json.tmp && \
  mv /tmp/container.json.tmp groups/browser/container.json'
```

## 7. Write the fetch script on the remote instance

```bash
SECRET_OCID="<vault_secret_ocid from step 3>"
ssh pa-cmd "mkdir -p /home/ubuntu/scripts && cat > /home/ubuntu/scripts/fetch-bws-token.sh << 'SCRIPT'
#!/bin/bash
# Fetches the BWS browser token from OCI Vault using Instance Principal and
# injects it into NanoClaw's browser container.json. Run after deploy or token rotation.
SECRET_OCID=\"$SECRET_OCID\"
TOKEN=\$(oci secrets secret-bundle get \\
  --secret-id \"\$SECRET_OCID\" \\
  --auth instance_principal \\
  --query 'data.\"secret-bundle-content\".content' \\
  --raw-output | base64 -d)

cd /home/ubuntu/nanoclaw-v2
jq --arg token \"\$TOKEN\" \\
  '.mcpServers.bitwarden_secrets.env.BWS_ACCESS_TOKEN = \$token' \\
  groups/browser/container.json > /tmp/container.json.tmp
mv /tmp/container.json.tmp groups/browser/container.json
echo \"Token injected into container.json\"
SCRIPT
chmod +x /home/ubuntu/scripts/fetch-bws-token.sh"
```

## 8. Run the fetch script to inject the token immediately

```bash
ssh pa-cmd 'bash /home/ubuntu/scripts/fetch-bws-token.sh'
```

The output should be `Token injected into container.json`.

## 9. Restart the browser agent container

Stop the running browser container — NanoClaw will respawn it on the next message:
```bash
ssh pa-cmd 'node -e "
  const {execSync} = require(\"child_process\");
  execSync(\"docker ps --filter name=browser --format {{.Names}}\", {encoding:\"utf8\"})
    .trim().split(\"\\n\").filter(Boolean)
    .forEach(n => { console.log(\"Stopping\", n); execSync(\"docker stop \" + n); });
" 2>/dev/null || true'
```

## 10. Confirm success

Tell the user:
- The BWS token is now stored in OCI Vault (`bws-browser-token`)
- The instance fetches it at runtime via Instance Principal — no credentials on disk
- The browser container has been restarted and will pick up the token on the next message
- To rotate the token: update it in Vault (repeat step 4 with the new value), then re-run `/home/ubuntu/scripts/fetch-bws-token.sh` on the instance and restart the browser container
