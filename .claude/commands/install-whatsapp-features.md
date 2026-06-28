Install the NanoClaw WhatsApp interactive features — **Polls**, **Events**, and **poll-vote receiving** — onto the remote instance, then rebuild the host and restart the service.

These features extend NanoClaw's **native Baileys WhatsApp adapter**, which exists only in the fork (`github.com/AmiTal4/nanoclaw`), not in upstream `nanocoai/nanoclaw`. The installer fetches the feature ref from the fork and merges it into the checkout. See `scripts/whatsapp-features/README.md` for the full design and the buttons-not-supported rationale.

Safe to re-run — `install.sh` is idempotent.

---

## 1. Check the SOCKS5 tunnel

`ssh pa-cmd` reaches the instance through the SOCKS5 proxy on `localhost:1080`, which is up whenever an `sshm pa` / `ssh pa` session is active.

**Windows** (PowerShell):
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```
**bash / macOS / Linux**:
```bash
nc -z -w1 localhost 1080 && echo open || echo closed
```

If `False` / `closed`, tell the user to run `/connect` first, then stop.

## 2. Confirm NanoClaw is cloned from the fork

The features require the native Baileys adapter. Verify it exists:
```bash
ssh pa-cmd 'grep -q "@whiskeysockets/baileys" /home/ubuntu/nanoclaw-v2/src/channels/whatsapp.ts && echo ok || echo missing'
```
- `ok` → continue.
- `missing` → the checkout is from upstream (or NanoClaw isn't set up). Tell the user the checkout must be cloned from `https://github.com/AmiTal4/nanoclaw.git` (re-run `/setup-instance` after pointing it at the fork), then stop.

## 3. Deploy the installer to the instance

`tr -d '\r'` strips Windows CRLF so the bash script runs cleanly:
```bash
ssh pa-cmd 'mkdir -p /home/ubuntu/whatsapp-features'
tr -d '\r' < scripts/whatsapp-features/install.sh \
  | ssh pa-cmd 'cat > /home/ubuntu/whatsapp-features/install.sh && chmod +x /home/ubuntu/whatsapp-features/install.sh'
```

## 4. Run the installer

Run through a **login shell** (`bash -lc`) so `pnpm` is on PATH:
```bash
ssh pa-cmd 'bash -lc "/home/ubuntu/whatsapp-features/install.sh"'
```

The script fetches + merges the feature ref from the fork (skips if already present), runs `pnpm install` + `pnpm build`, and restarts the user systemd service (reaping any process that escaped the `sg docker` cgroup to avoid an `EADDRINUSE :3000` crash-loop). Override defaults with env vars if needed — e.g. `FEATURE_REF=...`, `FORK_URL=...` (see the script header).

## 5. Verify

```bash
ssh pa-cmd 'cd /home/ubuntu/nanoclaw-v2 && \
  grep -c "name: '"'"'send_poll'"'"'" container/agent-runner/src/mcp-tools/core.ts && \
  grep -c "getAggregateVotesInPollMessage" src/channels/whatsapp.ts && \
  XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active "nanoclaw-v2-*.service"'
```
Expect `1`, a non-zero count, and `active`.

## 6. Tell the user

- Sending is live now; `send_poll` / `send_event` appear on the **next agent spawn** (the agent-runner is mounted read-only into containers — no image rebuild).
- To test end-to-end: ask an agent to send a poll to a wired WhatsApp chat, then vote. The agent should receive a `📊 Poll update` tally.
- **Limitation:** poll-vote decoding uses an in-memory cache, so votes are only tracked for polls sent **after** the most recent host restart.
