#!/bin/bash
# Installs the NanoClaw WhatsApp interactive features — Polls, Events, and
# poll-vote receiving — into a NanoClaw checkout on the instance, then rebuilds
# the host and restarts the service. Idempotent: safe to re-run.
#
# What the features add (all in the native Baileys WhatsApp adapter):
#   - send_poll  MCP tool  → native WhatsApp poll (single/multi-select)
#   - send_event MCP tool  → native WhatsApp event card (time/place/call link)
#   - inbound poll votes    → decrypted, aggregated, forwarded to the agent as a
#                             "Poll update" tally (DM polls wake the agent)
#   - approval polls        → ask_question/admin-approval cards render as a native
#                             single-select poll; tapping answers it (no typed
#                             /approve). Falls back to text outside 2-12 options.
#
# IMPORTANT — these features live in the FORK, not upstream NanoClaw.
# They extend the native Baileys adapter (src/channels/whatsapp.ts), which only
# exists in the fork (default: github.com/AmiTal4/nanoclaw). Upstream
# (nanocoai/nanoclaw) uses a different WhatsApp path and cannot take this patch.
# If your checkout was cloned from upstream, re-clone from the fork first.
#
# Mechanism: fetch the feature ref from the fork and merge it into the checkout,
# then `pnpm build` + restart the user systemd service. The agent-runner tools
# (send_poll/send_event) are mounted read-only into agent containers, so they
# take effect on the next agent spawn with no image rebuild.
#
# Config via env (all optional):
#   NANOCLAW_DIR   NanoClaw checkout            (default: /home/ubuntu/nanoclaw-v2)
#   FORK_URL       Git URL carrying the feature (default: https://github.com/AmiTal4/nanoclaw.git)
#   FEATURE_REF    Branch/tag/commit to install (default: feat/whatsapp-polls-events)
#   SKIP_RESTART   set to 1 to build but not restart the service
set -euo pipefail

NANOCLAW_DIR="${NANOCLAW_DIR:-/home/ubuntu/nanoclaw-v2}"
FORK_URL="${FORK_URL:-https://github.com/AmiTal4/nanoclaw.git}"
FEATURE_REF="${FEATURE_REF:-feat/whatsapp-polls-events}"
FORK_REMOTE="whatsapp-features"

log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$NANOCLAW_DIR/.git" ] || die "No NanoClaw checkout at $NANOCLAW_DIR — run /setup-instance first."
cd "$NANOCLAW_DIR"

CORE_TOOLS="container/agent-runner/src/mcp-tools/core.ts"
WA_ADAPTER="src/channels/whatsapp.ts"

# --- Prerequisite: the native Baileys adapter must be present ------------------
if [ ! -f "$WA_ADAPTER" ] || ! grep -q "@whiskeysockets/baileys" "$WA_ADAPTER" 2>/dev/null; then
  die "$WA_ADAPTER (native Baileys adapter) not found — this checkout is not the fork.
       Re-clone NanoClaw from $FORK_URL, then re-run."
fi

# --- Idempotency: already installed? -----------------------------------------
already_installed() {
  grep -q "name: 'send_poll'" "$CORE_TOOLS" 2>/dev/null \
    && grep -q "operation === 'poll'" "$WA_ADAPTER" 2>/dev/null \
    && grep -q "getAggregateVotesInPollMessage" "$WA_ADAPTER" 2>/dev/null \
    && grep -q "questionPolls" "$WA_ADAPTER" 2>/dev/null
}

if already_installed; then
  log "WhatsApp features already present in source — skipping fetch/merge."
else
  log "Fetching feature ref '$FEATURE_REF' from $FORK_URL"
  if git remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
    git remote set-url "$FORK_REMOTE" "$FORK_URL"
  else
    git remote add "$FORK_REMOTE" "$FORK_URL"
  fi
  git fetch --quiet "$FORK_REMOTE" "$FEATURE_REF"

  log "Merging feature ref into the checkout"
  if ! git merge --no-edit FETCH_HEAD; then
    git merge --abort || true
    die "Automatic merge failed — your checkout has diverged from the fork.
         Re-clone from $FORK_URL (or merge '$FEATURE_REF' manually), then re-run."
  fi

  already_installed || die "Merge completed but feature markers are missing — aborting before build."
  log "Source updated."
fi

# --- Build the host -----------------------------------------------------------
command -v pnpm >/dev/null 2>&1 || die "pnpm not on PATH — run this through a login shell (bash -lc) or install pnpm."
log "Installing dependencies (baileys etc.)"
pnpm install --prefer-offline
log "Building host (tsc → dist/)"
pnpm build

# --- Restart the service ------------------------------------------------------
if [ "${SKIP_RESTART:-0}" = "1" ]; then
  log "SKIP_RESTART=1 — built but not restarting. Restart the service to go live."
  exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
UNIT="$(systemctl --user list-units --type=service --all --plain --no-legend 'nanoclaw-v2-*.service' 2>/dev/null | awk '{print $1}' | head -1)"
[ -n "$UNIT" ] || die "Could not find the nanoclaw-v2 user service — restart NanoClaw manually."

log "Restarting $UNIT"
# The host is launched via 'sg docker', which escapes systemd's cgroup, so a
# plain restart can leave the old process holding port 3000 (EADDRINUSE) and the
# new one crash-loops. Stop, reap any escaped process, then start clean.
systemctl --user stop "$UNIT" || true
pkill -f "node .*${NANOCLAW_DIR}/dist/index.js" 2>/dev/null || true
sleep 3
systemctl --user reset-failed "$UNIT" 2>/dev/null || true

# Start, then poll. The 'sg docker' launch occasionally means the first `start`
# doesn't take, so retry once if it isn't active within ~20s.
started=0
for attempt in 1 2; do
  systemctl --user start "$UNIT" || true
  for _ in $(seq 1 10); do
    sleep 2
    if [ "$(systemctl --user is-active "$UNIT")" = "active" ]; then started=1; break; fi
  done
  [ "$started" = "1" ] && break
  log "Service not active yet — retrying start (attempt $attempt)"
  systemctl --user reset-failed "$UNIT" 2>/dev/null || true
done

if [ "$started" = "1" ]; then
  log "Done — $UNIT is active. Poll/event sending is live; send_poll/send_event"
  log "appear on the next agent spawn (agent-runner is mounted read-only)."
else
  die "$UNIT did not come up active. Check: journalctl --user -u $UNIT -n 50"
fi
