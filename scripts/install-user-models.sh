#!/usr/bin/env bash
# Install/update Ollama model entries in ~/.grok/config.toml (Grok requirement).
# Project .grok/config.toml cannot define [model.*] — only MCP/plugins/permissions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

CFG="${GROK_CONFIG:-$HOME/.grok/config.toml}"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"

python3 - "$CFG" "$OLLAMA_OPENAI_BASE" "$OLLAMA_ADMIN_MODEL" "$OLLAMA_FAST_MODEL" <<'PY'
import re
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
base = sys.argv[2]
admin_model = sys.argv[3]
fast_model = sys.argv[4]
text = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""

# Remove previous managed block if present
text = re.sub(
    r"\n?# --- linux-admin .*?models.*?---\n.*?# --- end linux-admin models ---\n?",
    "\n",
    text,
    flags=re.S,
)
# Also strip standalone ollama-admin/fast sections we may have written earlier
for name in ("ollama-admin", "ollama-fast"):
    text = re.sub(
        rf"\n?\[model\.{re.escape(name)}\]\n(?:[^\[]*\n)*",
        "\n",
        text,
    )

block = f"""
# --- linux-admin Ollama models (install-user-models.sh) ---
[model.ollama-admin]
model = "{admin_model}"
base_url = "{base}"
name = "Ollama Admin"
api_backend = "chat_completions"
context_window = 32768
temperature = 0.2
max_completion_tokens = 8192

[model.ollama-fast]
model = "{fast_model}"
base_url = "{base}"
name = "Ollama Fast"
api_backend = "chat_completions"
context_window = 16384
temperature = 0.3
max_completion_tokens = 4096
# --- end linux-admin models ---
"""
text = text.rstrip() + "\n" + block
cfg_path.write_text(text, encoding="utf-8")
print(f"wrote ollama-admin ({admin_model}) + ollama-fast ({fast_model})")
print(f"  base_url = {base}")
print(f"  config   = {cfg_path}")
PY
