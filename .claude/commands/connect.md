Bring up a **resilient SOCKS5 tunnel** to the PA instance as a background job, so `ssh pa-cmd` and `ALL_PROXY` work — and keep it alive (auto-reconnecting) for the rest of the session.

The tunnel is `scripts/pa-tunnel.py`: it holds a SOCKS5 proxy on `localhost:1080` over the OCI Bastion (using the `pa` host as its backing Bastion connection) and **auto-reconnects** on any drop, with SSH keepalives to avoid idle drops in the first place. Once it's up, **everything goes through `ssh pa-cmd`** — both one-off commands *and* interactive shells — so there's no need to open a separate `sshm pa` window.

## 1. Pre-flight checks

Terraform state exists:
```
test -f infra/terraform.tfstate && echo ok || echo missing
```
If missing, tell the user to run `/deploy` first and stop.

OCI auth is valid:
```
oci iam region list --profile pa --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run `! oci session authenticate --region il-jerusalem-1 --profile-name pa` and retry.

Python is available (the tunnel is a Python script):
```
python --version || python3 --version
```

## 2. Check for an existing connection

Is the SOCKS5 proxy already live on `localhost:1080`?

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```
**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo open || echo closed
```

If **open/True** → it's already connected. Tell the user they can use `ssh pa-cmd '<cmd>'` (or `ALL_PROXY=socks5://localhost:1080 <cmd>`) and stop.

## 3. Start the resilient tunnel in the background

Run the tunnel as a **background job** (it loops forever — do NOT block on it). From the repo root:
```
python scripts/pa-tunnel.py
```
Run this with `run_in_background: true`. (Use `python3` if `python` isn't on PATH.) The script provisions an OCI Bastion session on first connect (~30s) and then maintains the proxy, reconnecting automatically if it ever drops.

Then poll for the proxy to come up (up to ~60s):

**Windows:**
```powershell
for ($i=0; $i -lt 12; $i++) { if ((Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded) { 'up'; break }; Start-Sleep 5 }
```
**bash:**
```bash
for i in $(seq 1 12); do nc -z -w1 localhost 1080 2>/dev/null && { echo up; break; }; sleep 5; done
```

## 4. Verify and tell the user

Confirm the instance is reachable through the tunnel:
```
ssh pa-cmd 'echo ok; hostname'
```

Then tell the user:
- The SOCKS5 proxy is live on `localhost:1080` and **auto-reconnects** — it's running as a background job in this session.
- Run anything on the instance with **`ssh pa-cmd`** — a command (`ssh pa-cmd 'uptime'`) or an interactive shell (`ssh pa-cmd`).
- Other tools: `ALL_PROXY=socks5://localhost:1080 <command>`.
- The tunnel stops when this session ends (or when stopped). To run it independently in your own terminal instead: `python scripts/pa-tunnel.py`.

**Note for Claude (running remote commands):** always use `ssh pa-cmd '<cmd>'` — it's instant through the proxy. Do **not** use `ssh pa` directly: it exists only as the tunnel's backing Bastion connection (`pa-tunnel.py` dials it via `ssh -N pa`), and using it directly provisions a fresh ~30s Bastion session per call. If `ssh pa-cmd` fails with `Unable to connect to relay host`, the tunnel dropped — re-run `/connect` (or check the background job).
