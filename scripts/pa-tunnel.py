#!/usr/bin/env python3
"""Resilient SOCKS5 tunnel to the PA instance over the OCI Bastion.

Keeps a SOCKS5 proxy alive on localhost:1080 and **auto-reconnects** whenever it
drops -- replacing a bare interactive `sshm pa`, whose proxy dies on idle timeout
or when the window is closed, leaving `ssh pa-cmd` / `ALL_PROXY` dead.

Two layers of resiliency:
  1. SSH keepalives (ServerAliveInterval) stop the idle drops in the first place.
  2. A supervise loop re-establishes the tunnel (a fresh Bastion session, ~30s)
     on any disconnect, with capped exponential backoff. A connection that
     survives a while resets the backoff, so transient blips heal instantly while
     a hard outage doesn't hammer OCI.

Cross-platform (Windows / macOS / Linux), Python stdlib only.

Usage:
    python scripts/pa-tunnel.py            # run in a dedicated terminal; Ctrl-C to stop
    SOCKS_PORT=9050 python scripts/pa-tunnel.py

Uses the `Host pa` block in ~/.ssh/config (its `DynamicForward 1080` is what
opens the SOCKS proxy). Run `/setup-sshm` once first if `ssh pa` isn't set up.
"""
import os
import subprocess
import sys
import time

HOST = os.environ.get("PA_SSH_HOST", "pa")
PORT = os.environ.get("SOCKS_PORT", "1080")
BASE_BACKOFF = 2
MAX_BACKOFF = 30
STABLE_SECS = 60  # a session lasting at least this long resets the backoff

if os.name == "nt":
    os.system("")  # enable ANSI escape processing on Windows consoles

CYAN, RESET = "\033[1;36m", "\033[0m"


def log(msg):
    print(f"{CYAN}[pa-tunnel]{RESET} {msg}", flush=True)


def terminate(proc):
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def main():
    ssh_cmd = [
        "ssh", "-N",
        # Tunnel only (no remote shell). DynamicForward 1080 from the host config
        # opens the SOCKS proxy. Keepalives keep it alive through the Bastion/NAT;
        # ExitOnForwardFailure makes a busy local port fail fast so we retry.
        "-o", "ServerAliveInterval=20",
        "-o", "ServerAliveCountMax=3",
        "-o", "TCPKeepAlive=yes",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        HOST,
    ]

    log(f"Maintaining a resilient SOCKS5 proxy on localhost:{PORT} via '{HOST}'.")
    log(f"Use it with:  ssh pa-cmd '<cmd>'   or   ALL_PROXY=socks5://localhost:{PORT} <cmd>")
    log("Press Ctrl-C to stop.")

    backoff = BASE_BACKOFF
    while True:
        log("Connecting... (first connect provisions an OCI Bastion session, ~30s)")
        started = time.time()
        try:
            proc = subprocess.Popen(ssh_cmd)
        except FileNotFoundError:
            log("ERROR: `ssh` not found on PATH.")
            return 1

        try:
            code = proc.wait()
        except KeyboardInterrupt:
            log("Stopping (SOCKS proxy going down).")
            terminate(proc)
            return 0

        elapsed = int(time.time() - started)
        if elapsed >= STABLE_SECS:
            backoff = BASE_BACKOFF  # was healthy for a while -> heal fast

        reason = "exited cleanly" if code == 0 else f"dropped (exit {code})"
        log(f"Tunnel {reason} after {elapsed}s -- reconnecting in {backoff}s...")
        try:
            time.sleep(backoff)
        except KeyboardInterrupt:
            log("Stopping.")
            return 0
        backoff = min(backoff * 2, MAX_BACKOFF)


if __name__ == "__main__":
    sys.exit(main())
