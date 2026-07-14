#!/usr/bin/env bash
# Bootstrap (may use network once): venv, package install, optional ollama model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/bin:${PATH}"

echo "== linux-admin bootstrap =="

# uv
if ! command -v uv >/dev/null 2>&1; then
  echo "installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# Python MCP package
echo "syncing linux-admin-mcp venv..."
cd "$ROOT/mcp/linux_admin"
uv venv --python 3.12 .venv 2>/dev/null || uv venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip install -e ".[dev]"
cd "$ROOT"

# Ollama
if ! command -v ollama >/dev/null 2>&1; then
  echo "installing ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

if ! curl -sS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "starting ollama serve..."
  nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
  sleep 3
fi

# Default small model for reliability; override with LINUX_ADMIN_PULL_MODEL
PULL_MODEL="${LINUX_ADMIN_PULL_MODEL:-llama3.2:3b}"
if curl -sS --max-time 2 http://127.0.0.1:11434/api/tags | grep -q "$PULL_MODEL"; then
  echo "model already present: $PULL_MODEL"
else
  echo "pulling model: $PULL_MODEL"
  ollama pull "$PULL_MODEL"
fi

# Init creds metadata (no password)
if command -v linux-admin-creds >/dev/null 2>&1; then
  linux-admin-creds init --policy auto --backend file || true
fi

# Symlink convenience
mkdir -p "${HOME}/.local/bin"
ln -sfn "$ROOT/scripts/linux-admin" "${HOME}/.local/bin/linux-admin"
chmod +x "$ROOT/scripts/linux-admin" \
  "$ROOT/scripts/doctor.sh" \
  "$ROOT/scripts/doctor-offline.sh" \
  "$ROOT/scripts/bootstrap.sh" \
  "$ROOT/scripts/linux-admin-askpass" 2>/dev/null || true

echo
echo "bootstrap complete."
echo "  interactive:  linux-admin"
echo "  headless:     linux-admin -p \"list failed units\""
echo "  doctor:       linux-admin doctor"
"$ROOT/scripts/doctor.sh" || true
