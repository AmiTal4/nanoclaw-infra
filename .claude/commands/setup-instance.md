Provision the remote instance after first deploy: installs Git and clones the NanoClaw repo.
Safe to re-run — checks what's already done before acting.

All SSH commands run through the `pa-cmd` host alias (routes via existing SOCKS5 proxy on localhost:1080 — instant, no new Bastion session). Requires an active `sshm pa` / `ssh pa` connection.

---

## 1. Check for an existing SOCKS5 proxy

An active `sshm pa` / `ssh pa` session exposes a SOCKS5 proxy on `localhost:1080`. Check if it is reachable:

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

### If SOCKS5 is open — proceed

Tell the user: "Using the existing SOCKS5 proxy on localhost:1080 via `ssh pa-cmd` — no new Bastion session needed."
Continue to step 2.

### If SOCKS5 is not open — stop

Tell the user:
> No active connection detected on localhost:1080. Please run `/connect` to open an SSH session to the instance, then re-run `/setup-instance`.

Stop here — do not continue.

## 2. Check and install Git

```
ssh pa-cmd "git --version 2>/dev/null && echo installed || echo missing"
```

If missing:
```
ssh pa-cmd "sudo apt-get update -q && sudo apt-get install -y git"
```

## 3. Check and clone NanoClaw

```
ssh pa-cmd "test -d /home/ubuntu/nanoclaw-v2 && echo exists || echo missing"
```

If missing:
```
ssh pa-cmd "git clone https://github.com/nanocoai/nanoclaw /home/ubuntu/nanoclaw-v2"
```

If it already exists, skip and tell the user.

## 4. Done

Print a summary of what was done and suggest next steps:
```
Instance is ready.

Next steps:
  Follow the NanoClaw quickstart inside /home/ubuntu/nanoclaw-v2 to complete setup.
  Use /connect to open an interactive session on the instance.
```
