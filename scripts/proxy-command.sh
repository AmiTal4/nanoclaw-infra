#!/usr/bin/env bash
# OCI Bastion ProxyCommand — called by SSH, not directly by users.
# Creates a port-forwarding session and pipes stdin/stdout as the SSH tunnel.
# All log output goes to stderr so stdout stays clean for SSH.
#
# SSH passes the target host and port via %h and %p:
#   ProxyCommand /path/to/proxy-command.sh %h %p
set -euo pipefail
trap 'echo "[proxy] Error on line $LINENO — aborting." >&2' ERR

TARGET_HOST="$1"
TARGET_PORT="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-$SCRIPT_DIR/../infra}"

OCI_PROFILE="${OCI_PROFILE:-pa}"

echo "[proxy] Reading Terraform outputs..." >&2
BASTION_ID=$(terraform -chdir="$TF_DIR" output -raw bastion_id)
INSTANCE_IP=$(terraform -chdir="$TF_DIR" output -raw instance_private_ip)
REGION=$(terraform -chdir="$TF_DIR" output -raw region)
TF_SSH_PRIVATE_KEY=$(terraform -chdir="$TF_DIR" output -raw ssh_private_key_path 2>/dev/null || true)
TF_SSH_PUBLIC_KEY=$(terraform -chdir="$TF_DIR" output -raw ssh_public_key_path 2>/dev/null || true)

SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-${TF_SSH_PRIVATE_KEY:-$HOME/.ssh/id_rsa}}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-${TF_SSH_PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}}"

# Expand ~ manually since terraform outputs a literal tilde
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY/#\~/$HOME}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY/#\~/$HOME}"

echo "[proxy] Creating port-forwarding session..." >&2
SESSION_ID=$(oci bastion session create-port-forwarding \
  --bastion-id "$BASTION_ID" \
  --ssh-public-key-file "$SSH_PUBLIC_KEY" \
  --target-private-ip "$INSTANCE_IP" \
  --target-port 22 \
  --session-ttl 10800 \
  --display-name "proxy-$(date +%s)" \
  --region "$REGION" \
  --profile "$OCI_PROFILE" \
  --auth security_token \
  --query 'data.id' \
  --raw-output)

echo "[proxy] Session: $SESSION_ID" >&2
echo "[proxy] Waiting for ACTIVE state..." >&2

while true; do
  STATE=$(oci bastion session get \
    --session-id "$SESSION_ID" \
    --region "$REGION" \
    --profile "$OCI_PROFILE" \
    --auth security_token \
    --query 'data."lifecycle-state"' \
    --raw-output)
  echo "[proxy]   $STATE" >&2
  [[ "$STATE" == "ACTIVE" ]] && break
  [[ "$STATE" == "FAILED" || "$STATE" == "DELETED" ]] && echo "[proxy] Session $STATE. Aborting." >&2 && exit 1
  sleep 3
done

SSH_CMD=$(oci bastion session get \
  --session-id "$SESSION_ID" \
  --region "$REGION" \
  --profile "$OCI_PROFILE" \
  --auth security_token \
  --query 'data."ssh-metadata".command' \
  --raw-output)

# Extract the bastion jump host from the port-forwarding SSH command
# Format: ssh -i <key> -N -L <port>:<ip>:<port> -p 22 <sessionId>@host.bastion.<region>.oci.oraclecloud.com
BASTION_ENDPOINT=$(echo "$SSH_CMD" | grep -oE '[^ ]+@host\.bastion\.[^ ]+')

echo "[proxy] Tunnelling through $BASTION_ENDPOINT..." >&2

exec ssh \
  -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -W "$TARGET_HOST:$TARGET_PORT" \
  -p 22 \
  "$BASTION_ENDPOINT"
