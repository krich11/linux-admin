#!/usr/bin/env bash
# Install/update Ollama model entries in ~/.grok/config.toml (Grok requirement).
# Registers primary (LAN) + local fallback models.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

CFG="${GROK_CONFIG:-$HOME/.grok/config.toml}"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"

python3 - "$CFG" \
  "$OLLAMA_OPENAI_BASE" "$OLLAMA_ADMIN_MODEL" "$OLLAMA_FAST_MODEL" \
  "$OLLAMA_LOCAL_OPENAI_BASE" "$OLLAMA_LOCAL_MODEL" <<'PY'
import re
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
remote_base, admin_model, fast_model = sys.argv[2], sys.argv[3], sys.argv[4]
local_base, local_model = sys.argv[5], sys.argv[6]
text = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""

text = re.sub(
    r"\n?# --- linux-admin Ollama models.*?---\n.*?# --- end linux-admin models ---\n?",
    "\n",
    text,
    flags=re.S,
)
for name in ("ollama-admin", "ollama-fast", "ollama-local"):
    text = re.sub(
        rf"\n?\[model\.{re.escape(name)}\]\n(?:[^\[]*\n)*",
        "\n",
        text,
    )

block = f"""
# --- linux-admin Ollama models (install-user-models.sh) ---
# Primary: LAN Ollama
[model.ollama-admin]
model = "{admin_model}"
base_url = "{remote_base}"
name = "Ollama Admin (LAN)"
api_backend = "chat_completions"
context_window = 32768
temperature = 0.2
max_completion_tokens = 8192

[model.ollama-fast]
model = "{fast_model}"
base_url = "{remote_base}"
name = "Ollama Fast (LAN)"
api_backend = "chat_completions"
context_window = 16384
temperature = 0.3
max_completion_tokens = 4096

# Fallback: local Ollama on this machine (break-glass when LAN is down)
[model.ollama-local]
model = "{local_model}"
base_url = "{local_base}"
name = "Ollama Local (fallback)"
api_backend = "chat_completions"
context_window = 16384
temperature = 0.2
max_completion_tokens = 4096
# --- end linux-admin models ---
"""
text = text.rstrip() + "\n" + block
cfg_path.write_text(text, encoding="utf-8")
print(f"wrote ollama-admin  ({admin_model}) @ {remote_base}")
print(f"wrote ollama-fast   ({fast_model}) @ {remote_base}")
print(f"wrote ollama-local  ({local_model}) @ {local_base}")
print(f"  config = {cfg_path}")
PY
