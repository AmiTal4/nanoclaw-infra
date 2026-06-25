# Entry point for the PA infrastructure repo.
# Checks that Claude Code is installed, installs it if not, then launches it.

Write-Host "PA Infrastructure — starting up..."
Write-Host ""

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "Claude Code not found."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "Installing Claude Code via npm..."
        npm install -g @anthropic-ai/claude-code
        Write-Host ""
    } else {
        Write-Host "npm is not installed. Please install Node.js first:"
        Write-Host "  https://nodejs.org/en/download"
        Write-Host ""
        Write-Host "Then re-run this script."
        exit 1
    }
}

Write-Host "Launching Claude Code — type /install to get started."
Write-Host ""
claude
