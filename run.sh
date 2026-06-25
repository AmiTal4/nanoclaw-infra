#!/usr/bin/env bash
# Entry point for the PA infrastructure repo.
# Checks that Claude Code is installed, installs it if not, then launches it.
set -euo pipefail

echo "PA Infrastructure — starting up..."
echo ""

if ! command -v claude &>/dev/null; then
  echo "Claude Code not found."
  if command -v npm &>/dev/null; then
    echo "Installing Claude Code via npm..."
    npm install -g @anthropic-ai/claude-code
    echo ""
  else
    echo "npm is not installed. Please install Node.js first:"
    echo "  https://nodejs.org/en/download"
    echo ""
    echo "Then re-run this script."
    exit 1
  fi
fi

echo "Launching Claude Code — type /install to get started."
echo ""
exec claude
