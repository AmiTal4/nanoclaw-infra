#!/bin/bash
# Bake whisper.cpp + ffmpeg + a ggml model into ONE NanoClaw agent-group image,
# so that group's voice-note transcription needs no on-demand install and no
# runtime model download (agent containers run under egress lockdown).
#
# Run on the instance. It rebuilds the group's image tag in place (FROM the
# agent base image), so the group's next spawn picks it up — no host restart.
#
# Config via env:
#   GROUP_IMAGE_TAG  the per-group image to (re)build  (REQUIRED unless GROUP_ID given)
#                    e.g. nanoclaw-agent-v2-<slug>:<groupId>
#   GROUP_ID         resolve GROUP_IMAGE_TAG from the DB for this agent group id
#   NANOCLAW_DIR     NanoClaw checkout (default: /home/ubuntu/nanoclaw-v2) — used with GROUP_ID
#   BASE_IMAGE       base to build FROM (default: <repo>:latest derived from the tag)
#   MODEL            ggml model: base | small | medium (default: base)
#
# CAVEAT: if the agent later runs install_packages, NanoClaw rebuilds the group
# image from the base WITHOUT whisper — re-run this script after that.
#
# The agent must also be told to use it (see README): point its instructions at
#   ffmpeg -nostdin -loglevel error -i <file>.ogg -ar 16000 -ac 1 -f wav /tmp/v.wav -y
#   whisper-cli -m /opt/whisper/models/ggml-<MODEL>.bin -l <lang> -nt -f /tmp/v.wav
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NANOCLAW_DIR="${NANOCLAW_DIR:-/home/ubuntu/nanoclaw-v2}"
MODEL="${MODEL:-base}"

log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Resolve the group image tag from the DB if only GROUP_ID was given.
if [ -z "${GROUP_IMAGE_TAG:-}" ] && [ -n "${GROUP_ID:-}" ]; then
  GROUP_IMAGE_TAG="$(cd "$NANOCLAW_DIR" && node -e "
    const D=require('better-sqlite3');
    const db=new D('data/v2.db',{readonly:true});
    const r=db.prepare('SELECT image_tag FROM container_configs WHERE agent_group_id=?').get('${GROUP_ID}');
    db.close();
    if(!r||!r.image_tag){process.stderr.write('no image_tag for ${GROUP_ID} — the group has no per-group image yet (run install_packages once, or set GROUP_IMAGE_TAG)\n');process.exit(1);}
    process.stdout.write(r.image_tag);
  ")" || die "could not resolve image tag for GROUP_ID=$GROUP_ID"
fi

[ -n "${GROUP_IMAGE_TAG:-}" ] || die "set GROUP_IMAGE_TAG (or GROUP_ID) — e.g. nanoclaw-agent-v2-<slug>:<groupId>"
BASE_IMAGE="${BASE_IMAGE:-${GROUP_IMAGE_TAG%%:*}:latest}"

log "Building whisper image"
echo "  group image : $GROUP_IMAGE_TAG"
echo "  base image  : $BASE_IMAGE"
echo "  model       : $MODEL"

DOCKER_BUILDKIT=1 docker build \
  --build-arg "BASE=$BASE_IMAGE" \
  --build-arg "MODEL=$MODEL" \
  -t "$GROUP_IMAGE_TAG" \
  -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

log "Verifying whisper-cli + model in the image"
docker run --rm --entrypoint bash "$GROUP_IMAGE_TAG" -lc \
  "whisper-cli --help >/dev/null 2>&1 && test -f /opt/whisper/models/ggml-${MODEL}.bin && command -v ffmpeg >/dev/null && echo OK" \
  | grep -q OK || die "verification failed — whisper-cli / model / ffmpeg missing in the image"

log "Done. '$GROUP_IMAGE_TAG' now has whisper-cli + ffmpeg + ggml-${MODEL}. The"
log "group's next agent spawn uses it (no host restart needed)."
