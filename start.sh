#!/usr/bin/env bash
set -e

# Ensure core-daemon is running (system service started at boot)
if ! systemctl is-active --quiet core-daemon; then
  echo "[INFO] Starting core-daemon service..."
  sudo systemctl start core-daemon
fi

# Small delay to be safe
sleep 2

# Start CORE GUI in background
echo "[INFO] Launching CORE GUI..."
core-gui >/tmp/core-gui.log 2>&1 &
disown
echo "[SUCCESS] CORE GUI started (check /tmp/core-gui.log for logs)"
