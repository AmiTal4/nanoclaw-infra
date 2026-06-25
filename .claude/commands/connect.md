Connect to the PA instance via OCI Bastion. Creates a managed-SSH session, then prints the final SSH command for the user to run.

Steps:

## 1. Pre-flight check

Verify Terraform state exists:
```
test -f infra/terraform.tfstate && echo "ok" || echo "missing"
```
If missing, tell the user to run `/deploy` first and stop.

## 2. Read Terraform outputs

Run from the repo root using `-chdir=infra`:
```
terraform -chdir=infra output -raw bastion_id
terraform -chdir=infra output -raw instance_id
terraform -chdir=infra output -raw instance_private_ip
terraform -chdir=infra output -raw region
```
If any command fails, stop and tell the user to run `/deploy` first.

## 3. Create a managed-SSH session

```
oci bastion session create-managed-ssh \
  --bastion-id "<bastion_id>" \
  --ssh-public-key-file "$HOME/.ssh/id_rsa.pub" \
  --target-resource-id "<instance_id>" \
  --target-os-username ubuntu \
  --session-ttl 10800 \
  --display-name "claude-connect-$(date +%s)" \
  --region "<region>" \
  --profile pa \
  --auth security_token \
  --query 'data.id' \
  --raw-output
```

## 4. Poll until ACTIVE — max 30 attempts, sleep 5s between each

```
oci bastion session get \
  --session-id "<session_id>" \
  --region "<region>" \
  --profile pa \
  --auth security_token \
  --query 'data."lifecycle-state"' \
  --raw-output
```
Print the state each poll. If FAILED or DELETED, report the error and stop. If 30 attempts pass without ACTIVE, report timeout and stop.

## 5. Extract the bastion jump endpoint

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
This gives something like: `ocid1.bastionsession...@host.bastion.il-jerusalem-1.oci.oraclecloud.com`

## 6. Build the final SSH command

Construct from parts (do NOT use sed/string replacement on OCI's template — it breaks on paths with spaces and double `<privateKey>` occurrences):
```
ssh \
  -i "$HOME/.ssh/id_rsa" \
  -o "ProxyCommand=ssh -i \"$HOME/.ssh/id_rsa\" -W %h:%p -p 22 <bastion_endpoint>" \
  -o StrictHostKeyChecking=no \
  -D 1080 \
  -p 22 \
  ubuntu@<instance_private_ip>
```

## 7. Hand off to the user

Print the final command clearly. Then explain:
- Claude's terminal cannot forward a TTY — the user must run it themselves
- Suggest: `! <paste the command>` (the `!` prefix runs it in their active terminal)
- Once connected, SOCKS5 proxy is live on localhost:1080
- onecli: `ALL_PROXY=socks5://localhost:1080 onecli ...`

If OCI auth has expired (401 error at any step), tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry from step 3.
