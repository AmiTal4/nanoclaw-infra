Register the PA instance in ~/.ssh/config so sshm and plain ssh work via OCI Bastion.
Run once after terraform apply, or re-run to update an existing entry.

Steps:

## 0. Check sshm is installed

```
command -v sshm
```

If not found, detect the OS and offer to install:

**Windows (PowerShell — run via `!` prefix in Claude Code):**
```powershell
irm https://raw.githubusercontent.com/Gu1llaum-3/sshm/main/install/windows.ps1 | iex
```

**macOS:**
```bash
brew install Gu1llaum-3/sshm/sshm
```

**Linux:**
```bash
curl -sSL https://raw.githubusercontent.com/Gu1llaum-3/sshm/main/install/unix.sh | bash
```

Tell the user: "sshm is not installed. You can install it with the command above, or manually from https://github.com/gu1llaum-3/sshm. After installing, re-run `/setup-sshm`."
Stop and wait — do not continue until the user confirms sshm is installed.

## 1. Read Terraform outputs

Run from the repo root using `-chdir=infra`:
```
terraform -chdir=infra output -raw instance_private_ip
terraform -chdir=infra output -raw ssh_private_key_path
```
If either command fails, tell the user to run `/deploy` first and stop.

Also resolve the absolute path to proxy-command.sh from the repo root:
```
realpath scripts/proxy-command.sh
```

## 2. Detect the operating system

```
uname -s
```
- Starts with MINGW, MSYS, or CYGWIN → Windows (Git Bash)
- Otherwise → Linux/macOS

## 3. Resolve paths for the SSH config

Expand `~` in the `ssh_private_key_path` output to the actual home directory (Terraform stores a literal tilde).

On **Windows (Git Bash)**, convert POSIX paths to mixed format (C:/...) so Windows OpenSSH can read them:
```
cygpath -m "<expanded_ssh_private_key_path>"
cygpath -m "<absolute_path_to_proxy-command.sh>"
```
On **Linux/macOS**, use paths as-is.

## 4. Remove any existing `Host pa` block

Use Python3 for cross-platform correctness (handles CRLF, first-line at EOF, and missing file):
```
python3 -c "
import re, os
path = os.path.expanduser('~/.ssh/config')
if not os.path.exists(path):
    open(path, 'w').close()
    print('Created empty ~/.ssh/config')
else:
    content = open(path, 'rb').read().decode('utf-8', errors='replace')
    cleaned = re.sub(r'(?m)^Host pa[ \t]*\r?\n(?:[ \t]+.*\r?\n)*', '', content)
    open(path, 'w', newline='').write(cleaned)
    print('Removed existing Host pa block')
"
```

## 5. Append the new block to ~/.ssh/config

Use the resolved paths from step 3. **Always wrap paths in double quotes** — paths containing spaces (e.g. `C:/Users/<username>/...`) cause OpenSSH to report "extra arguments at end of line" without quotes.

The ProxyCommand differs by OS:

**Windows (Git Bash):** Use the full Windows path to bash so Windows OpenSSH calls the right interpreter regardless of PATH. Find it with:
```
cygpath -m "$(command -v bash)"
```
Then write:
```
Host pa
  HostName <instance_private_ip>
  User ubuntu
  IdentityFile "<ssh_private_key_path>"
  ProxyCommand "<bash_exe_path>" "<proxy_command_path>" %h %p
  DynamicForward 1080
  StrictHostKeyChecking accept-new
```

**Linux/macOS:**
```
Host pa
  HostName <instance_private_ip>
  User ubuntu
  IdentityFile <ssh_private_key_path>
  ProxyCommand bash "<proxy_command_path>" %h %p
  DynamicForward 1080
  StrictHostKeyChecking accept-new
```

Note: proxy-command.sh runs `terraform` and `oci` CLI — both must be on PATH in the bash environment that OpenSSH invokes. If `sshm pa` silently fails, first try `ssh pa-cmd 'echo ok'` (only works if already connected via an existing `pa` session); then fall back to:
```
bash scripts/proxy-command.sh <instance_private_ip> 22
```

## 6. Append the `Host pa-cmd` block to ~/.ssh/config

First remove any existing `Host pa-cmd` block using the same Python3 approach as step 4:
```
python3 -c "
import re, os
path = os.path.expanduser('~/.ssh/config')
content = open(path, 'rb').read().decode('utf-8', errors='replace')
cleaned = re.sub(r'(?m)^Host pa-cmd[ \t]*\r?\n(?:[ \t]+.*\r?\n)*', '', content)
open(path, 'w', newline='').write(cleaned)
print('Removed existing Host pa-cmd block')
"
```

Then append the new block. Use the same `<instance_private_ip>` and `<ssh_private_key_path>` resolved in steps 1–3. The ProxyCommand differs by OS:

**Windows (Git Bash):** Resolve the path to `connect.exe` with:
```
cygpath -m /mingw64/bin/connect.exe
```
Then write:
```
Host pa-cmd
  HostName <instance_private_ip>
  User ubuntu
  IdentityFile "<ssh_private_key_path>"
  ProxyCommand "<connect_exe_path>" -S 127.0.0.1:1080 %h %p
  StrictHostKeyChecking accept-new
```

**Linux/macOS:**
```
Host pa-cmd
  HostName <instance_private_ip>
  User ubuntu
  IdentityFile <ssh_private_key_path>
  ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
  StrictHostKeyChecking accept-new
```

Note: `pa-cmd` routes through the SOCKS5 proxy exposed by an active `pa` session. It is instant (no new Bastion session) but requires `sshm pa` or `ssh pa` to already be running.

## 7. Confirm and print next steps

Print the exact blocks written to ~/.ssh/config, then tell the user:
- Connect with: `sshm pa` or `ssh pa`
- SOCKS5 proxy will be on localhost:1080 once connected
- Once connected, run one-off commands instantly with: `ssh pa-cmd '<command>'`
- onecli: `ALL_PROXY=socks5://localhost:1080 onecli ...`
