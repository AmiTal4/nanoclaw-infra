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
oci iam region list --profile pa --auth security_token --query 'data[0].name' --raw-output
```
If this fails with a 401/auth error, tell the user to run:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 2. Detect the operating system

```
uname -s
```
- Starts with MINGW, MSYS, or CYGWIN → Windows
- Darwin → macOS
- Otherwise → Linux

## 3. Open a new terminal window running `sshm pa`

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

## 4. Confirm and tell the user

After launching, tell the user:
- A new terminal window is opening with `sshm pa` — it takes ~30s to connect (OCI Bastion session provisioning)
- Once connected, SOCKS5 proxy is live on `localhost:1080`
- To use it with onecli: `ALL_PROXY=socks5://localhost:1080 onecli ...`
- The connection lasts up to 3 hours (session TTL)
