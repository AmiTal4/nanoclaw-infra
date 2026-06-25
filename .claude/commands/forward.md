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

## 4. Open a new terminal window with the port-forward SSH command

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

## 5. Confirm and tell the user

After launching, tell the user:
- A new terminal window is opening the tunnel — takes ~30s (OCI Bastion provisioning)
- Once connected: `localhost:<local_port>` → instance port `<remote_port>`
- The terminal window holds the tunnel open — close it to stop forwarding
- To run multiple port forwards simultaneously, run `/forward` again with a different port
