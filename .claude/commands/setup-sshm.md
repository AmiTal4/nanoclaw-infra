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
```
If this fails, tell the user to run `/deploy` first and stop.

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

On **Windows (Git Bash)**, convert POSIX paths to mixed format (C:/...) so Windows OpenSSH can read them:
```
cygpath -m "$HOME/.ssh/id_rsa"
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

Use the resolved paths from step 3. **Always wrap paths in double quotes** — paths containing spaces (e.g. `C:/Users/Amit Tal/...`) cause OpenSSH to report "extra arguments at end of line" without quotes:
```
Host pa
  HostName <instance_private_ip>
  User ubuntu
  IdentityFile "<ssh_private_key_path>"
  ProxyCommand bash "<proxy_command_path>" %h %p
  DynamicForward 1080
  StrictHostKeyChecking accept-new
```
Always prefix ProxyCommand with `bash "..."` so it works regardless of which SSH client reads the config.

Note: proxy-command.sh runs `terraform` and `oci` CLI — both must be on PATH in the bash environment that OpenSSH invokes. If `sshm pa` silently fails, test with:
```
bash scripts/proxy-command.sh <instance_private_ip> 22
```

## 6. Confirm and print next steps

Print the exact block written to ~/.ssh/config, then tell the user:
- Connect with: `sshm pa` or `ssh pa`
- SOCKS5 proxy will be on localhost:1080 once connected
- onecli: `ALL_PROXY=socks5://localhost:1080 onecli ...`
