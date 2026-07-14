#!/usr/bin/env bash
# Install/update Ollama model entries in ~/.grok/config.toml (Grok requirement).
#
# Flags:
#   --set-default   also set [models].default = ollama-admin (bootstrap only;
#                   everyday launches leave last-used / user default alone)
#   --pick          re-select OLLAMA_ADMIN_MODEL from LAN library (T4-aware)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

SET_DEFAULT=0
DO_PICK=0
for arg in "$@"; do
  case "$arg" in
    --set-default) SET_DEFAULT=1 ;;
    --pick) DO_PICK=1 ;;
  esac
done

# If env still says auto (before lib-env resolution overwrote it), force pick.
# Re-source raw intent from config file:
_raw_admin="$(grep -E '^OLLAMA_ADMIN_MODEL=' "$ROOT/config/ollama.env" 2>/dev/null | tail -1 || true)"
if [[ "$_raw_admin" == *'auto'* ]] && [[ "$DO_PICK" -eq 0 ]]; then
  # Everyday install without --pick: keep whatever is already in grok config
  :
fi

# Bootstrap / explicit: pick best model on remote for T4
if [[ "$DO_PICK" -eq 1 ]]; then
  if picked="$(python3 "$ROOT/scripts/pick-admin-model.py" "$OLLAMA_BASE_URL" 2>/tmp/linux-admin-pick.err)"; then
    OLLAMA_ADMIN_MODEL="$picked"
    echo "selected LAN admin model (T4-aware): $OLLAMA_ADMIN_MODEL" >&2
    cat /tmp/linux-admin-pick.err >&2 || true
  else
    echo "warning: auto-pick failed; keeping OLLAMA_ADMIN_MODEL=${OLLAMA_ADMIN_MODEL}" >&2
    cat /tmp/linux-admin-pick.err >&2 || true
  fi
fi

CFG="${GROK_CONFIG:-$HOME/.grok/config.toml}"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"

python3 - "$CFG" \
  "$OLLAMA_OPENAI_BASE" "$OLLAMA_ADMIN_MODEL" "$OLLAMA_FAST_MODEL" \
  "$OLLAMA_LOCAL_OPENAI_BASE" "$OLLAMA_LOCAL_MODEL" \
  "$SET_DEFAULT" <<'PY'
import re
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
remote_base, admin_model, fast_model = sys.argv[2], sys.argv[3], sys.argv[4]
local_base, local_model = sys.argv[5], sys.argv[6]
set_default = sys.argv[7] == "1"
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
# Primary: LAN Ollama (weights chosen for T4-class GPU when using --pick)
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

# Fallback: local Ollama on this machine
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

if set_default:
    # Upsert [models].default = "ollama-admin" without clobbering other keys
    if re.search(r"(?m)^\[models\]\s*$", text):
        # Replace default only inside the first [models] section roughly
        parts = re.split(r"(?m)^(\[models\]\s*\n)", text, maxsplit=1)
        if len(parts) == 3:
            head, hdr, rest = parts
            # rest until next [
            m = re.match(r"(.*?)(?=^\[|\Z)", rest, flags=re.S | re.M)
            section = m.group(1) if m else rest
            tail = rest[len(section) :]
            if re.search(r"(?m)^default\s*=", section):
                section = re.sub(
                    r"(?m)^default\s*=\s*.*$",
                    'default = "ollama-admin"',
                    section,
                    count=1,
                )
            else:
                section = 'default = "ollama-admin"\n' + section
            text = head + hdr + section + tail
    else:
        text = '[models]\ndefault = "ollama-admin"\n\n' + text.lstrip()

cfg_path.write_text(text, encoding="utf-8")
print(f"wrote ollama-admin  ({admin_model}) @ {remote_base}")
print(f"wrote ollama-fast   ({fast_model}) @ {remote_base}")
print(f"wrote ollama-local  ({local_model}) @ {local_base}")
if set_default:
    print('set [models].default = "ollama-admin"')
print(f"  config = {cfg_path}")
PY

# Record last auto-pick for humans (keep default as auto so re-bootstrap re-picks)
if [[ "$DO_PICK" -eq 1 && -n "${OLLAMA_ADMIN_MODEL:-}" ]]; then
  echo "OLLAMA_ADMIN_MODEL currently resolved to: ${OLLAMA_ADMIN_MODEL}"
fi
