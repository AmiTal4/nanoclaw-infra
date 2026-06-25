Forward a local port to a port on the PA instance (or any host reachable from it) over the OCI Bastion tunnel.
Runs the tunnel as a background process you can stop on demand.

Usage:
  /forward <port>                              — same port both sides, remote host = localhost
  /forward <local>:<remote_port>               — different ports, remote host = localhost
  /forward <local>:<remote_host>:<remote_port> — different ports, explicit remote host
  /forward stop <port>                         — stop a running forward for that local port
  /forward stop all                            — stop all running forwards

Examples:
  /forward 3000                      → localhost:3000 → instance:3000
  /forward 8080:3000                 → localhost:8080 → instance:3000
  /forward 10254:172.17.0.1:10254    → localhost:10254 → docker host:10254
  /forward stop 3000                 → kill the background SSH for port 3000

The remote host is the host SSH jumps to **from inside the instance**. Common values:
- `localhost` — a service running on the instance itself (default)
- `172.17.0.1` — the Docker host (docker0 bridge gateway on Linux)

PID files are stored in `~/.ssh/forward-<local_port>.pid`.

Steps:

## 1. Parse the argument

**If the argument starts with `stop`:**
- Extract the port (or "all") from the argument.
- If "all": glob `~/.ssh/forward-*.pid`, kill each PID, delete all files.
- Otherwise: read `~/.ssh/forward-<port>.pid`, kill the PID, delete the file.
- Tell the user which forward(s) were stopped and exit.

**Otherwise**, parse the forward spec. The remote host defaults to `localhost` if not specified:
- `<port>` → local=port, remote_host=localhost, remote_port=port
- `<local>:<remote_port>` → local=local, remote_host=localhost, remote_port=remote_port
- `<local>:<remote_host>:<remote_port>` → all three explicit

If the user mentions "docker host" without giving an IP, use `172.17.0.1`.

If no argument is provided, ask the user: "Which port do you want to forward? (e.g. 3000, 8080:3000, or 10254:172.17.0.1:10254)"

## 2. Pre-flight checks

### 2a. Detect the OS

```
uname -s
```
- Starts with MINGW, MSYS, or CYGWIN → Windows
- Darwin → macOS
- Otherwise → Linux

### 2b. Check for an existing SOCKS5 proxy

Check if `localhost:1080` is listening — if so, `ssh -L` will connect instantly by reusing the existing Bastion session.

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

Note the result (open/closed) — it affects the timing message in step 4, but **do not stop here**. Always proceed to start the tunnel.

### 2c. Check sshm is installed (only if SOCKS5 not running)

If localhost:1080 was **closed**, check:
```
command -v sshm
```
If not found, tell the user to run `/setup-sshm` first and stop.

### 2d. Check OCI auth is valid (only if SOCKS5 not running)

If localhost:1080 was **closed**, check:
```
oci iam region list --profile pa --auth security_token --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 3. Start the tunnel in the background

Run this in Bash (works on Windows via Git Bash, macOS, and Linux):

```bash
ssh -L <local_port>:<remote_host>:<remote_port> -N pa &
SSH_PID=$!
echo $SSH_PID > ~/.ssh/forward-<local_port>.pid
echo "PID $SSH_PID"
```

Store the PID — you'll need it to report to the user and to support `/forward stop`.

## 4. Confirm and tell the user

Tell the user:
- The tunnel is running in the background (PID `<pid>`)
- If SOCKS5 was **open**: tunnel is up immediately — `localhost:<local_port>` → `<remote_host>:<remote_port>` on the instance
- If SOCKS5 was **closed**: tunnel will be ready in ~30s while OCI Bastion provisions
- To stop: run `/forward stop <local_port>`
- PID file: `~/.ssh/forward-<local_port>.pid`
