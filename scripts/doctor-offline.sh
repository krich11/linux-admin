#!/usr/bin/env bash
# Assert CORE path does not require WAN. Optional online tools may be absent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${ROOT}/mcp/linux_admin/.venv/bin:${HOME}/.local/bin:${PATH}"

echo "== linux-admin doctor-offline (core path) =="

# 1) Standard doctor (local components)
"$ROOT/scripts/doctor.sh"

# 2) Ensure MCP config does not use live npx -y / uvx registry installs for core servers
# Ignore comments; flag actual command/args lines only.
if grep -R --include='config.toml' -E '^\s*(command|args)\s*=' "$ROOT/.grok" 2>/dev/null \
  | grep -E 'npx|uvx' \
  | grep -vE '^\s*#' ; then
  # Further require -y or bare uvx install pattern
  if grep -R --include='config.toml' -E 'npx[^\n]*-y|command\s*=\s*"uvx"|command\s*=\s*\x27uvx\x27' "$ROOT/.grok" 2>/dev/null \
    | grep -vE '^\s*#|/#|comment' ; then
    echo "  [FAIL] project config appears to use runtime registry installers (npx -y / uvx)"
    exit 1
  fi
fi
echo "  [OK]  no npx -y / uvx runtime installers in project MCP commands"

# 3) Ollama is loopback
if grep -E 'base_url\s*=' "$ROOT/.grok/config.toml" | grep -v '127.0.0.1' | grep -v 'localhost' | grep -v '^#' ; then
  echo "  [WARN] non-loopback base_url found — ensure core default stays local"
else
  echo "  [OK]  model base_url points at loopback"
fi

# 4) Core tools work without invoking network binaries
"$ROOT/mcp/linux_admin/.venv/bin/python" - <<'PY'
from linux_admin_mcp.executil import ALLOWED_BINARIES, DENIED_BINARIES, resolve_binary
assert "curl" in DENIED_BINARIES
assert "wget" in DENIED_BINARIES
assert "systemctl" in ALLOWED_BINARIES
resolve_binary("systemctl")
from linux_admin_mcp.tools.resources import disk_df
from linux_admin_mcp.tools.network import ip_addr
assert disk_df()["returncode"] == 0
assert ip_addr()["returncode"] == 0
print("  [OK]  allowlist + local probes")
PY

# 5) Optional: brief Ollama completion if models present
if curl -sS --max-time 2 http://127.0.0.1:11434/api/tags >/tmp/oa.json 2>/dev/null; then
  if python3 -c 'import json; d=json.load(open("/tmp/oa.json")); exit(0 if d.get("models") else 1)'; then
    if curl -sS --max-time 120 http://127.0.0.1:11434/api/generate \
      -d '{"model":"llama3.2:3b","prompt":"Reply with exactly: pong","stream":false}' \
      2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("response","")[:80])' \
      | grep -qi pong; then
      echo "  [OK]  ollama local generate (llama3.2:3b)"
    else
      # try whatever first model is
      MODEL=$(python3 -c 'import json; d=json.load(open("/tmp/oa.json")); print(d["models"][0]["name"])')
      echo "  [WARN] llama3.2:3b pong skip; first model is $MODEL (still local)"
    fi
  fi
fi

echo
echo "doctor-offline: PASS (core path)"
exit 0
