Provision the remote instance after first deploy: installs Git and clones the NanoClaw repo.
Safe to re-run — checks what's already done before acting.

All SSH commands run non-interactively through a Bastion session so no manual connection is needed.

---

## 1. Read Terraform outputs

```
terraform -chdir=infra output -raw bastion_id
terraform -chdir=infra output -raw instance_id
terraform -chdir=infra output -raw instance_private_ip
terraform -chdir=infra output -raw region
```
If any fail, tell the user to run `/deploy` first and stop.

## 2. Check for an existing SOCKS5 proxy (fast path)

If an `sshm pa` / `ssh pa` session is already active it exposes a SOCKS5 proxy on `localhost:1080`. Route SSH through it to skip the 30 s managed-SSH bastion provisioning.

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

### If SOCKS5 is open — skip to step 6 using this SSH helper:

```bash
ssh \
  -i "$HOME/.ssh/id_rsa" \
  -o "ProxyCommand=nc -X 5 -x localhost:1080 %h %p" \
  -o StrictHostKeyChecking=no \
  -o BatchMode=yes \
  ubuntu@<instance_private_ip> \
  "<remote command>"
```

Tell the user: "Using the existing SOCKS5 proxy on localhost:1080 — no new Bastion session needed."
Then proceed directly to step 6.

### If SOCKS5 is not open — continue with steps 3–5 below.

## 3. Create a managed-SSH Bastion session

```
oci bastion session create-managed-ssh \
  --bastion-id "<bastion_id>" \
  --ssh-public-key-file "$HOME/.ssh/id_rsa.pub" \
  --target-resource-id "<instance_id>" \
  --target-os-username ubuntu \
  --session-ttl 10800 \
  --display-name "claude-setup-$(date +%s)" \
  --region "<region>" \
  --profile pa \
  \
  --query 'data.id' \
  --raw-output
```

## 4. Poll until ACTIVE — max 30 attempts, sleep 5s between each

```
oci bastion session get \
  --session-id "<session_id>" \
  --region "<region>" \
  --profile pa \
  \
  --query 'data."lifecycle-state"' \
  --raw-output
```
Stop with an error if FAILED, DELETED, or 30 attempts elapse.

## 5. Extract the bastion jump endpoint

```
oci bastion session get \
  --session-id "<session_id>" \
  --region "<region>" \
  --profile pa \
  \
  --query 'data."ssh-metadata".command' \
  --raw-output \
| grep -oE '[^ ]+@host\.bastion\.[^ ]+'
```

Define the SSH helper for steps 6–7:
```
ssh \
  -i "$HOME/.ssh/id_rsa" \
  -o "ProxyCommand=ssh -i \"$HOME/.ssh/id_rsa\" -W %h:%p -p 22 <bastion_endpoint>" \
  -o StrictHostKeyChecking=no \
  -o BatchMode=yes \
  ubuntu@<instance_private_ip> \
  "<remote command>"
```

## 6. Check and install Git

```
# Check
<ssh> "git --version 2>/dev/null && echo installed || echo missing"
```

If missing:
```
<ssh> "sudo apt-get update -q && sudo apt-get install -y git"
```

## 7. Check and clone NanoClaw

```
# Check
<ssh> "test -d /home/ubuntu/nanoclaw-v2 && echo exists || echo missing"
```

If missing:
```
<ssh> "git clone https://github.com/nanocoai/nanoclaw /home/ubuntu/nanoclaw-v2"
```

If it already exists, skip and tell the user.

## 8. Done

Print a summary of what was done and suggest next steps:
```
Instance is ready.

Next steps:
  Follow the NanoClaw quickstart inside /home/ubuntu/nanoclaw-v2 to complete setup.
  Use /connect to open an interactive session on the instance.
```
