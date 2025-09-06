#!/usr/bin/env bash
set -euo pipefail

# =============================
# CONFIG / LOGGING
# =============================
LOG="/tmp/core_emane_install.$(date +%s).log"
exec > >(tee -a "$LOG") 2>&1
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Starting CORE+EMANE install on $(lsb_release -sd 2>/dev/null || echo 'Ubuntu') ($(uname -m))"

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "[WARN] This script targets ARM64 (aarch64). Detected: $(uname -m)"
fi

# Ensure pipx bin dir is available in THIS shell and future shells
export PATH="$HOME/.local/bin:$PATH"
if ! grep -qs 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# =============================
# OPTIONAL DESKTOP (GNOME)
# Comment these three lines if you already have a working desktop/login.
# =============================
sudo apt update && sudo apt -y upgrade
sudo apt install -y ubuntu-desktop gdm3
sudo dpkg-reconfigure -f noninteractive gdm3 || true

# =============================
# BASE TOOLS & BUILD DEPS
# =============================
sudo apt-get update -y
sudo apt-get install -y ca-certificates xterm psmisc wget git unzip \
  python3 python3-venv python3-pip python3-tk \
  iproute2 iputils-ping tcpdump \
  build-essential automake libtool pkg-config \
  libpcap-dev libpcre3-dev libprotobuf-dev libxml2-dev protobuf-compiler uuid-dev \
  gawk g++ libreadline-dev make

# =============================
# WORKSPACE
# =============================
mkdir -p "$HOME/Documents"
cd "$HOME/Documents"

# =============================
# EMANE FROM SOURCE (v1.5.1)
# =============================
if [[ ! -d emane ]]; then
  git clone https://github.com/adjacentlink/emane.git
fi
cd emane
git fetch --tags
git checkout v1.5.1
./autogen.sh
./configure --prefix=/usr
make -j"$(nproc)"
sudo make install
sudo ldconfig
cd ..

# =============================
# CORE FROM SOURCE
# - ./setup.sh sets up /opt/core/venv and installs 'inv' via pipx.
# - We then run 'inv install -p /usr'.
# =============================
if [[ ! -d core ]]; then
  git clone https://github.com/coreemu/core.git
fi
cd core
./setup.sh

# Resolve 'inv' path robustly after setup.sh (pipx places it in ~/.local/bin)
INV_BIN="$(command -v inv || true)"
if [[ -z "${INV_BIN}" ]]; then
  # Try common location explicitly
  if [[ -x "$HOME/.local/bin/inv" ]]; then
    INV_BIN="$HOME/.local/bin/inv"
  else
    echo "[ERROR] 'inv' not found on PATH after setup.sh. Check pipx installation/log above."
    echo "[HINT ] You can try: python3 -m pip install --user pipx && pipx ensurepath && ~/.local/bin/pipx install invoke"
    exit 1
  fi
fi

# Install CORE system-wide shims to /usr
"${INV_BIN}" install -p /usr
cd ..

# =============================
# PROTOC (ARM64) FOR EMANE PY BINDINGS INTO CORE VENV
# =============================
PROTOC_ZIP="protoc-27.2-linux-aarch_64.zip"
if [[ ! -d "$HOME/Documents/protoc" ]]; then
  wget -q "https://github.com/protocolbuffers/protobuf/releases/download/v27.2/${PROTOC_ZIP}"
  mkdir -p protoc && unzip -q "$PROTOC_ZIP" -d protoc
fi

# Rebuild/install EMANE Python bindings with CORE's venv Python
cd "$HOME/Documents/emane"
git checkout v1.5.1
./autogen.sh
PYTHON=/opt/core/venv/bin/python ./configure --prefix=/usr
cd src/python && make clean
PATH="$HOME/Documents/protoc/bin:$PATH" make
sudo /opt/core/venv/bin/pip install .
cd "$HOME/Documents"

# =============================
# CORE LOGGING CONFIG
# =============================
sudo mkdir -p /opt/core/etc /var/log/core
sudo tee /opt/core/etc/logging.conf >/dev/null <<'EOF'
{"version":1,"disable_existing_loggers":false,
 "formatters":{"default":{"format":"%(asctime)s %(levelname)s %(name)s: %(message)s"}},
 "handlers":{"console":{"class":"logging.StreamHandler","level":"INFO","formatter":"default","stream":"ext://sys.stdout"},
             "file":{"class":"logging.handlers.RotatingFileHandler","level":"INFO","formatter":"default",
                     "filename":"/var/log/core/core-daemon.log","maxBytes":10485760,"backupCount":5}},
 "root":{"level":"INFO","handlers":["console","file"]},
 "loggers":{"core":{"level":"INFO","handlers":["console","file"],"propagate":false}}}
EOF
sudo chmod 644 /opt/core/etc/logging.conf
sudo install -d -m 0755 -o root -g root /var/log/core

# =============================
# SYSTEMD UNIT FOR core-daemon (non-blocking)
# =============================
sudo tee /etc/systemd/system/core-daemon.service >/dev/null <<'EOF'
[Unit]
Description=CORE network emulator gRPC daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/core-daemon --grpc-address 127.0.0.1 --grpc-port 50051 --log-config /opt/core/etc/logging.conf
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now core-daemon

# =============================
# VERIFY
# =============================
echo "[INFO] Checking gRPC port 50051..."
if ss -lntp | grep -q 50051; then
  echo "[SUCCESS] core-daemon is listening on 127.0.0.1:50051"
else
  echo "[ERROR] core-daemon not listening on 50051"
  systemctl status core-daemon --no-pager || true
  journalctl -u core-daemon -n 200 --no-pager || true
  exit 1
fi

echo
echo "[DONE] Installation complete."
echo "      Launch GUI from your desktop session:"
echo "        core-gui"
echo "      Logs: $LOG"
