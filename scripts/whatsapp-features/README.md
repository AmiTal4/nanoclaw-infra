# WhatsApp interactive features

Adds richer-than-text capabilities to NanoClaw's native Baileys WhatsApp adapter:

| Capability | How the agent uses it |
|------------|-----------------------|
| **Polls** | `send_poll({ name, options, allowMultipleAnswers?, to? })` — renders as a native WhatsApp poll recipients tap to vote. |
| **Events** | `send_event({ name, startTime, endTime?, description?, location?, call?, to? })` — renders as a native event card (add-to-calendar). |
| **Poll-vote receiving** | When people vote, the adapter decrypts and aggregates the votes and forwards a `📊 Poll update` tally to the agent. DM polls wake the agent on each vote; group poll votes are recorded without waking it. |
| **Contacts** | `send_contact({ name, phone, phones?, org?, email?, to? })` — sends a tappable vCard. Incoming contact cards arrive as a `📇 Contact card` summary plus the raw `.vcf` in `/workspace/inbox/<messageId>/`. |
| **Replies / quoted messages** | When someone uses WhatsApp's **reply** feature, the quoted message is surfaced to the agent. The adapter reads Baileys' `contextInfo` (`quotedMessage` + `participant` + `stanzaId`) and sets `content.replyTo = { sender, text, id }`; the agent-runner formatter renders it as a `<quoted_message from="…">…</quoted_message>` block with a `reply_to="…"` attribute, so the agent sees exactly which message was referenced. Replies to a media message show a type tag (`[image]`, `[voice message]`, `[document: …]`, …); the quoted author is the assistant's name when it was the bot's own message, otherwise a best-effort name (phone digits). |
| **Approval polls** | Admin-approval cards (self-mod `install_packages`/`add_mcp_server`, OneCLI credentials, a2a/permission gates) and the agent's `ask_user_question` render as a **native single-select poll** instead of a text prompt. The approver **taps** an option — the vote is mapped back to its value and answered through the existing approval pipeline, so no typed `/approve` is needed. Module approvals show three options — **Approve**, **Reject**, **Reject with reason…** (the third holds the reject and captures your next DM as a one-line reason relayed to the agent). These polls are answered silently (never forwarded to the agent as a `📊 Poll update`). Falls back to the text/slash prompt when the option count is outside WhatsApp's 2–12 poll range. |

Buttons are intentionally **not** included: Baileys 7 has no high-level send API
for interactive buttons, and WhatsApp has effectively deprecated them for
non-Business-API clients (they frequently don't render).

**Approval polls caveat:** answering an approval rides the same poll-vote
**decrypt** path as poll-vote receiving. The text/slash prompt is fully replaced
by the poll (poll-only by design), so if a vote can't be decrypted the card
can't be answered — re-trigger the approval to get a fresh poll.

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
4. **Stamps the upgrade marker** (`scripts/upgrade-state.ts set`) when present —
   see the note below.
5. Restarts the user systemd service — stopping it, reaping any process that
   escaped the cgroup via `sg docker` (avoids the `EADDRINUSE :3000`
   crash-loop), then starting clean, and **fails loudly if the host comes up
   crash-looping behind the upgrade tripwire** (which `systemctl is-active`
   alone would hide).

The agent-runner tools (`send_poll`/`send_event`) are mounted **read-only** into
agent containers, so they take effect on the next agent spawn — no image rebuild.

> **Note — feature ref + the upgrade tripwire.** `FEATURE_REF`
> (`feat/whatsapp-polls-events`) tracks a fork branch that periodically merges
> **upstream NanoClaw**, so the merge in step 2 can bump the NanoClaw version.
> NanoClaw refuses to boot (and crash-loops) when its recorded version marker
> doesn't match `package.json` unless the upgrade went through a sanctioned
> path — so step 4 stamps the marker after a clean build. If you ever see
> `Upgrade tripwire` in the logs, run `pnpm exec tsx scripts/upgrade-state.ts set`
> in the checkout and restart.

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

## Voice transcription (`whisper/`)

Inbound delivery puts voice notes in `/workspace/inbox/<messageId>/<file>.ogg`, but
the agent still needs **speech-to-text** to read them. Agents shouldn't install it
on demand — it's slow and ephemeral (fresh container each spawn), and the model
can't be fetched at runtime because containers run under **egress lockdown**.

`whisper/build-whisper-image.sh` bakes **whisper.cpp + ffmpeg + a ggml model** into
**one agent group's** image (FROM the agent base), so that group's spawns have it
ready, fully offline. whisper.cpp (not Python/torch) keeps it small and fast on
ARM. Run it on the instance:

```bash
# Edna's group, base model (≈148MB, fair Hebrew accuracy, ~2s for a short clip)
GROUP_ID=<edna-agent-group-id> MODEL=base /home/ubuntu/whatsapp-features/whisper/build-whisper-image.sh
```

`MODEL` can be `base` | `small` | `medium` (bigger = better accuracy, larger image,
slower on ARM). The script rebuilds the group's image tag in place; the next spawn
uses it — no host restart.

Then point the agent at it (e.g. in the group's `CLAUDE.local.md`):

```
ffmpeg -nostdin -loglevel error -i <inbox-file>.ogg -ar 16000 -ac 1 -f wav /tmp/v.wav -y
whisper-cli -m /opt/whisper/models/ggml-<MODEL>.bin -l he -nt -f /tmp/v.wav
```

**Caveat:** if the agent later runs `install_packages`, NanoClaw rebuilds the group
image from the base **without** whisper — re-run the script afterward. (Scope is one
group; for fleet-wide STT, bake the same layers into the base `container/Dockerfile`
in the fork instead.)
