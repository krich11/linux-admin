#!/usr/bin/env bash
# Ensure linux-admin MCP is registered in ~/.grok/config.toml (user scope)
# so it loads even when project folder-trust is flaky. Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/.." && pwd)"
CFG="${GROK_CONFIG:-$HOME/.grok/config.toml}"
MCP_BIN="${ROOT}/mcp/linux_admin/.venv/bin/linux-admin-mcp"

if [[ ! -x "$MCP_BIN" ]]; then
  echo "register-user-mcp: missing $MCP_BIN (run bootstrap)" >&2
  exit 1
fi

mkdir -p "$(dirname "$CFG")"
touch "$CFG"

python3 - "$CFG" "$MCP_BIN" <<'PY'
import re
import sys
from pathlib import Path

cfg, mcp_bin = Path(sys.argv[1]), sys.argv[2]
text = cfg.read_text(encoding="utf-8") if cfg.exists() else ""

block = f'''
# --- linux-admin MCP (register-user-mcp.sh) ---
[mcp_servers.linux-admin]
command = "{mcp_bin}"
args = []
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
tool_timeouts = {{ service_restart = 90, apt_list_upgradable = 180, journal_since = 60 }}
# --- end linux-admin MCP ---
'''

text = re.sub(
    r"\n?# --- linux-admin MCP.*?---\n.*?# --- end linux-admin MCP ---\n?",
    "\n",
    text,
    flags=re.S,
)
# also drop a prior bare section if we wrote one without markers
text = re.sub(
    r"\n?\[mcp_servers\.linux-admin\]\n(?:[^\[]*\n)*",
    "\n",
    text,
)
text = text.rstrip() + "\n" + block
cfg.write_text(text, encoding="utf-8")
print(f"registered user MCP linux-admin → {mcp_bin}")
PY
