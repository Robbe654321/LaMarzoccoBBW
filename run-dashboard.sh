#!/usr/bin/env bash
set -euo pipefail

# Simple launcher for the Tkinter dashboard on Raspberry Pi.
# - Creates/uses a virtualenv in .venv
# - Installs minimal deps by default (good for 512MB RAM)
# - Copies example config if missing
# - Starts the dashboard
#
# Usage:
#   ./run-dashboard.sh         # minimal deps
#   ./run-dashboard.sh --full  # install full deps incl. cloud libs

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

if [[ ! -d .venv ]]; then
  echo "[setup] Creating virtualenv (.venv)"
  python3 -m venv .venv
fi

source .venv/bin/activate

REQ_FILE="requirements-dashboard-min.txt"
if [[ "${1:-}" == "--full" ]]; then
  REQ_FILE="requirements-dashboard.txt"
fi

MARKER=".venv/.deps_installed_$(basename "$REQ_FILE")"
if [[ ! -f "$MARKER" ]]; then
  echo "[setup] Installing dependencies from $REQ_FILE"
  pip install --upgrade pip
  pip install -r "$REQ_FILE"
  mkdir -p "$(dirname "$MARKER")"
  echo "ok" > "$MARKER"
fi

if [[ ! -f config/dashboard.toml ]]; then
  echo "[setup] Creating config/dashboard.toml from example"
  mkdir -p config
  cp -n config/dashboard.example.toml config/dashboard.toml || true
fi

echo "[run] Starting dashboard"
exec python dashboard.py

