#!/usr/bin/env bash
# Install Ollama model entries into ~/.grok/config.toml (Grok requirement).
# Project .grok/config.toml cannot define [model.*] — only MCP/plugins/permissions.
set -euo pipefail

CFG="${GROK_CONFIG:-$HOME/.grok/config.toml}"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"

if grep -q '\[model\.ollama-admin\]' "$CFG" 2>/dev/null; then
  echo "ollama-admin model already present in $CFG"
  exit 0
fi

cat >> "$CFG" << 'EOF'

# --- linux-admin local Ollama models (install-user-models.sh) ---
[model.ollama-admin]
model = "llama3.2:3b"
base_url = "http://127.0.0.1:11434/v1"
name = "Ollama Admin"
api_backend = "chat_completions"
context_window = 16384
temperature = 0.2
max_completion_tokens = 4096

[model.ollama-fast]
model = "llama3.2:3b"
base_url = "http://127.0.0.1:11434/v1"
name = "Ollama Fast"
api_backend = "chat_completions"
context_window = 8192
temperature = 0.3
max_completion_tokens = 2048
# --- end linux-admin models ---
EOF

echo "installed ollama-admin + ollama-fast into $CFG"
echo "Note: Grok project config only carries MCP; models must live in user config."
