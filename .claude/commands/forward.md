Forward a local port to a port on the PA instance (or any host reachable from it) over the OCI Bastion tunnel.
Runs the tunnel as a detached background process you can stop on demand.

Usage:
  /forward <port>                              — same port both sides, remote host = localhost
  /forward <local>:<remote_port>               — different ports, remote host = localhost
  /forward <local>:<remote_host>:<remote_port> — explicit remote host
  /forward stop <port>                         — stop a running forward for that local port
  /forward stop all                            — stop all running forwards

Examples:
  /forward 3000                      → localhost:3000 → instance:3000
  /forward 8080:3000                 → localhost:8080 → instance:3000
  /forward 10254:172.17.0.1:10254    → localhost:10254 → docker host:10254
  /forward stop 3000                 → kill the background SSH for port 3000

The remote host is resolved **from inside the instance**. Common values:
- `localhost` — a service on the instance itself (default)
- `172.17.0.1` — the Docker host (docker0 bridge gateway on Linux)

PID files are stored in `~/.ssh/forward-<local_port>.pid` (POSIX path) /
`$env:USERPROFILE\.ssh\forward-<local_port>.pid` (Windows).

Steps:

## 1. Parse the argument

**If the argument starts with `stop`:**
- Extract the port (or "all").
- **Windows (PowerShell):** `$fwdPid = (Get-Content "$env:USERPROFILE\.ssh\forward-<port>.pid").Trim(); Stop-Process -Id $fwdPid -Force; Remove-Item "$env:USERPROFILE\.ssh\forward-<port>.pid"` (use `$fwdPid`, not `$pid` — `$pid` is a reserved PowerShell variable)
- **macOS/Linux (Bash):** `kill $(cat ~/.ssh/forward-<port>.pid) && rm ~/.ssh/forward-<port>.pid`
- If "all", repeat for every `forward-*.pid` file.
- Tell the user which forward(s) were stopped and exit.

**Otherwise**, parse the forward spec (remote host defaults to `localhost`):
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

Check if `localhost:1080` is listening.

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

Note the result — it determines which SSH host alias to use in step 3:
- **open** → use `pa-cmd` (routes through SOCKS5, instant, no auth needed)
- **closed** → use `pa` (provisions a new Bastion session, ~30s)

### 2c. Check sshm is installed (only if SOCKS5 not running)

If localhost:1080 was **closed**, check:
```
command -v sshm
```
If not found, tell the user to run `/setup-sshm` first and stop.

### 2d. Check OCI auth is valid (only if SOCKS5 not running)

If localhost:1080 was **closed**, check:
```
oci iam region list --profile pa --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 3. Start the tunnel as a detached background process

Use `SSH_HOST=pa-cmd` if SOCKS5 is running, otherwise `SSH_HOST=pa`.

On Windows, Git Bash subshells kill child processes on exit — use `Start-Process` to detach properly:

**Windows (PowerShell):**
```powershell
$p = Start-Process -FilePath "ssh" -ArgumentList "-L", "<local_port>:<remote_host>:<remote_port>", "-N", "<SSH_HOST>" -WindowStyle Hidden -PassThru
$p.Id | Out-File "$env:USERPROFILE\.ssh\forward-<local_port>.pid" -Encoding utf8
Start-Sleep 2
if (-not $p.HasExited) { "alive: PID $($p.Id)" } else { "process exited with code $($p.ExitCode)" }
```

**macOS / Linux (Bash):**
```bash
nohup ssh -L <local_port>:<remote_host>:<remote_port> -N <SSH_HOST> >/dev/null 2>&1 &
SSH_PID=$!
disown $SSH_PID
echo $SSH_PID > ~/.ssh/forward-<local_port>.pid
sleep 2 && kill -0 $SSH_PID && echo "alive: PID $SSH_PID" || echo "failed"
```

If the process exits immediately, report the failure to the user.

## 4. Confirm and tell the user

Tell the user:
- The tunnel is running in the background (PID `<pid>`)
- `localhost:<local_port>` → `<remote_host>:<remote_port>` on the instance
- If SOCKS5 was **open**: tunnel connected instantly via `pa-cmd`
- If SOCKS5 was **closed**: tunnel will be ready in ~30s (Bastion provisioning via `pa`)
- To stop: run `/forward stop <local_port>`
