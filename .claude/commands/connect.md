Connect to the PA instance by opening a new terminal window running `sshm pa`.

Steps:

## 1. Pre-flight checks

Verify Terraform state exists:
```
test -f infra/terraform.tfstate && echo "ok" || echo "missing"
```
If missing, tell the user to run `/deploy` first and stop.

Check sshm is installed:
```
command -v sshm
```
If not found, tell the user to install it (see `/setup-sshm` step 0 for platform-specific install commands) and stop.

Check OCI auth is valid:
```
oci iam region list --profile pa --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 2. Check for an existing connection

Check if the SOCKS5 proxy is already live on `localhost:1080` (present when any `sshm pa` / `ssh pa` session is active):

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

If **open** → tell the user:

> Already connected — SOCKS5 proxy is live on `localhost:1080`.
> - `ALL_PROXY=socks5://localhost:1080 <command>` to reach the instance
> - To open a second interactive shell session anyway, reply `again`.

Stop here unless the user explicitly asks to open another session.

## 3. Detect the operating system

```
uname -s
```
- Starts with MINGW, MSYS, or CYGWIN → Windows
- Darwin → macOS
- Otherwise → Linux

## 4. Open a new terminal window running `sshm pa`

**Windows** — use PowerShell to launch a new window:
```powershell
Start-Process powershell -ArgumentList '-NoExit', '-Command', 'sshm pa'
```

**macOS** — use osascript to open a new Terminal tab:
```bash
osascript -e 'tell application "Terminal" to do script "sshm pa"'
```

**Linux** — try common terminal emulators in order:
```bash
x-terminal-emulator -e "bash -c 'sshm pa; exec bash'" 2>/dev/null \
  || gnome-terminal -- bash -c "sshm pa; exec bash" 2>/dev/null \
  || xterm -e "bash -c 'sshm pa; exec bash'" &
```

## 5. Confirm and tell the user

After launching, tell the user:
- A new terminal window is opening with `sshm pa` — it takes ~30s to connect (OCI Bastion session provisioning)
- Once connected, SOCKS5 proxy is live on `localhost:1080`
- To use it with onecli: `ALL_PROXY=socks5://localhost:1080 onecli ...`
- The connection lasts up to 3 hours (session TTL)

**Note for Claude (running remote commands):** once this connection is up, run one-off remote commands with `ssh pa-cmd '<cmd>'` — it tunnels through the SOCKS5 proxy and is **instant**. Do **not** use `ssh pa` for scripted commands: it provisions a fresh OCI Bastion session (~30s) per call. The SOCKS5 proxy drops when the `sshm pa` window closes — if `ssh pa-cmd` fails with `Unable to connect to relay host`, re-run `/connect`.
