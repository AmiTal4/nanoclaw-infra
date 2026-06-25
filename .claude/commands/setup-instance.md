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

## 2. Create a managed-SSH Bastion session

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
  --auth security_token \
  --query 'data.id' \
  --raw-output
```

## 3. Poll until ACTIVE — max 30 attempts, sleep 5s between each

```
oci bastion session get \
  --session-id "<session_id>" \
  --region "<region>" \
  --profile pa \
  --auth security_token \
  --query 'data."lifecycle-state"' \
  --raw-output
```
Stop with an error if FAILED, DELETED, or 30 attempts elapse.

## 4. Extract the bastion jump endpoint

```
oci bastion session get \
  --session-id "<session_id>" \
  --region "<region>" \
  --profile pa \
  --auth security_token \
  --query 'data."ssh-metadata".command' \
  --raw-output \
| grep -oE '[^ ]+@host\.bastion\.[^ ]+'
```

## 5. Define the SSH helper

All remote commands below use this form — run them via the Bash tool:
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
