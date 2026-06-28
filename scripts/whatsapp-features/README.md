# WhatsApp interactive features

Adds three capabilities to NanoClaw's native Baileys WhatsApp adapter so agents
can run richer interactions than plain text:

| Capability | How the agent uses it |
|------------|-----------------------|
| **Polls** | `send_poll({ name, options, allowMultipleAnswers?, to? })` — renders as a native WhatsApp poll recipients tap to vote. |
| **Events** | `send_event({ name, startTime, endTime?, description?, location?, call?, to? })` — renders as a native event card (add-to-calendar). |
| **Poll-vote receiving** | When people vote, the adapter decrypts and aggregates the votes and forwards a `📊 Poll update` tally to the agent. DM polls wake the agent on each vote; group poll votes are recorded without waking it. |

Buttons are intentionally **not** included: Baileys 7 has no high-level send API
for interactive buttons, and WhatsApp has effectively deprecated them for
non-Business-API clients (they frequently don't render).

The feature ref this installer pulls also carries a fix for **inbound
attachments** (images, documents, and voice notes): media now lands in the
session's `/workspace/inbox/<messageId>/` like every other channel, instead of a
host directory that was never mounted into the container. Note this only delivers
the file — **transcribing** voice notes needs a separate speech-to-text step the
agent does not have out of the box.

## Prerequisite — these features live in the fork

They extend the **native Baileys adapter** (`src/channels/whatsapp.ts`), which
exists only in the fork (default `github.com/AmiTal4/nanoclaw`). Upstream
`nanocoai/nanoclaw` uses a different WhatsApp path and **cannot** take this
change. If your instance was set up from upstream, re-clone NanoClaw from the
fork before installing.

## Install

Use the **`/install-whatsapp-features`** skill (copies this folder to the
instance and runs `install.sh` over the Bastion tunnel), or run it directly on
the instance:

```bash
bash -lc '/home/ubuntu/whatsapp-features/install.sh'
```

`install.sh` is **idempotent**. It:

1. Verifies the native Baileys adapter is present (fails with guidance if not).
2. If the feature markers are already in the source, skips fetch/merge.
   Otherwise it fetches `FEATURE_REF` from the fork and merges it.
3. Runs `pnpm install` + `pnpm build` (the host).
4. Restarts the user systemd service — stopping it, reaping any process that
   escaped the cgroup via `sg docker` (avoids the `EADDRINUSE :3000`
   crash-loop), then starting clean.

The agent-runner tools (`send_poll`/`send_event`) are mounted **read-only** into
agent containers, so they take effect on the next agent spawn — no image rebuild.

### Config (env, all optional)

| Var | Default | Purpose |
|-----|---------|---------|
| `NANOCLAW_DIR` | `/home/ubuntu/nanoclaw-v2` | NanoClaw checkout |
| `FORK_URL` | `https://github.com/AmiTal4/nanoclaw.git` | Git URL carrying the feature |
| `FEATURE_REF` | `feat/whatsapp-polls-events` | Branch / tag / commit to install |
| `SKIP_RESTART` | `0` | `1` = build but don't restart |

## Verify

```bash
# tools wired
grep -c "name: 'send_poll'" container/agent-runner/src/mcp-tools/core.ts   # 1
# adapter handles poll/event + decodes votes
grep -c "operation === 'poll'\|getAggregateVotesInPollMessage" src/channels/whatsapp.ts
# service healthy
systemctl --user is-active 'nanoclaw-v2-*.service'
```

Then ask an agent to send a poll to a wired WhatsApp destination and vote on it —
you should see a `📊 Poll update` arrive back to the agent.
