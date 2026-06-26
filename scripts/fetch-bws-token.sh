#!/bin/bash
# Fetches the BWS browser token from OCI Vault via Instance Principal auth and
# injects it into NanoClaw's config DB (data/v2.db). Run after deploy or token
# rotation. No restart needed — NanoClaw regenerates container.json from the DB
# at the next browser spawn.
#
# Why the DB and not container.json: NanoClaw v2 treats container.json as a
# generated artifact (materializeContainerJson rewrites it from the DB at every
# spawn). Editing the file is silently overwritten; the DB is the source of truth.
#
# The secret OCID is read from a sibling file (bws-secret.ocid) written by the
# /setup-bitwarden skill from `terraform output -raw vault_secret_ocid`, so this
# script carries no environment-specific identifiers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCID_FILE="$SCRIPT_DIR/bws-secret.ocid"
OCI_BIN="${OCI_BIN:-/home/ubuntu/bin/oci}"

if [ ! -f "$OCID_FILE" ]; then
  echo "ERROR: $OCID_FILE not found — run /setup-bitwarden to create it" >&2
  exit 1
fi
SECRET_OCID="$(tr -d '[:space:]' < "$OCID_FILE")"

TOKEN=$("$OCI_BIN" secrets secret-bundle get \
  --secret-id "$SECRET_OCID" \
  --auth instance_principal \
  --query 'data."secret-bundle-content".content' \
  --raw-output | base64 -d)

if [ -z "$TOKEN" ]; then
  echo "ERROR: fetched empty token from Vault" >&2
  exit 1
fi

BWS_TOKEN="$TOKEN" node "$SCRIPT_DIR/inject-bws-token.cjs"
