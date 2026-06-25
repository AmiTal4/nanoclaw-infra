Forward a local port to a port on the PA instance over the OCI Bastion tunnel.

Usage: /forward <local_port>:<remote_port>  or  /forward <port>  (same port both sides)

Examples:
  /forward 3000        → localhost:3000 → instance:3000
  /forward 8080:3000   → localhost:8080 → instance:3000

Steps:

## 1. Parse the port argument

Read the argument passed to this skill. Accept two formats:
- `<port>` — use the same port for both local and remote
- `<local_port>:<remote_port>` — different local and remote ports

If no argument is provided, ask the user: "Which port do you want to forward? (e.g. 3000 or 8080:3000)"

## 2. Pre-flight checks

Check sshm is installed:
```
command -v sshm
```
If not found, tell the user to run `/setup-sshm` first and stop.

Check OCI auth is valid:
```
oci iam region list --profile pa --auth security_token --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 3. Detect the OS

```
uname -s
```
- Starts with MINGW, MSYS, or CYGWIN → Windows
- Darwin → macOS
- Otherwise → Linux

## 4. Check for an existing SOCKS5 proxy (fast path)

The `pa` SSH host config includes `DynamicForward 1080`, so any active `sshm pa` or `ssh pa` session already exposes a SOCKS5 proxy on `localhost:1080` that can reach **all** remote ports — no new tunnel needed.

Check if `localhost:1080` is listening:

**Windows (PowerShell):**
```powershell
(Test-NetConnection -ComputerName localhost -Port 1080 -WarningAction SilentlyContinue).TcpTestSucceeded
```

**macOS / Linux (Bash):**
```bash
nc -z -w1 localhost 1080 2>/dev/null && echo "open" || echo "closed"
```

If the port is **open** → tell the user:

> A SOCKS5 proxy is already running on `localhost:1080` from an existing `sshm pa` session. You can reach instance port `<remote_port>` through it without opening a new tunnel:
>
> ```
> # curl
> curl --proxy socks5://localhost:1080 http://localhost:<remote_port>/
>
> # any command that respects ALL_PROXY
> ALL_PROXY=socks5://localhost:1080 <command>
> ```
>
> If you still want a dedicated `-L` forward on `localhost:<local_port>`, it will be instant (reuses the existing Bastion session). Run `/forward <local_port>:<remote_port>` again and type `force` to proceed.

Stop here unless the user confirms they want to proceed with the dedicated forward anyway.

## 5. Open a new terminal window with the port-forward SSH command

The command to run in the new terminal is:
```
ssh -L <local_port>:localhost:<remote_port> -N pa
```

`-N` means no remote command — just hold the tunnel open. The `pa` host alias handles bastion session creation via proxy-command.sh automatically.

**Windows:**
```powershell
Start-Process powershell -ArgumentList '-NoExit', '-Command', 'ssh -L <local_port>:localhost:<remote_port> -N pa'
```

**macOS:**
```bash
osascript -e 'tell application "Terminal" to do script "ssh -L <local_port>:localhost:<remote_port> -N pa"'
```

**Linux:**
```bash
x-terminal-emulator -e "bash -c 'ssh -L <local_port>:localhost:<remote_port> -N pa; exec bash'" 2>/dev/null \
  || gnome-terminal -- bash -c "ssh -L <local_port>:localhost:<remote_port> -N pa; exec bash" 2>/dev/null \
  || xterm -e "bash -c 'ssh -L <local_port>:localhost:<remote_port> -N pa; exec bash'" &
```

## 6. Confirm and tell the user

After launching, tell the user:
- A new terminal window is opening the tunnel — takes ~30s (OCI Bastion provisioning)
- Once connected: `localhost:<local_port>` → instance port `<remote_port>`
- The terminal window holds the tunnel open — close it to stop forwarding
- To run multiple port forwards simultaneously, run `/forward` again with a different port
