#!/usr/bin/env bash
# Core path health check (does not require WAN for success of local components).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${ROOT}/mcp/linux_admin/.venv/bin:${HOME}/.local/bin:${PATH}"

OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
FAIL=0

ok() { printf '  [OK]  %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=1; }
warn() { printf '  [WARN] %s\n' "$*"; }

echo "== linux-admin doctor =="
echo "root: $ROOT"

# Grok
if command -v grok >/dev/null 2>&1; then
  ok "grok: $(command -v grok)"
else
  bad "grok not on PATH"
fi

# Ollama API
if curl -sS --max-time 3 "${OLLAMA_URL}/api/tags" >/tmp/linux-admin-ollama-tags.json 2>/dev/null; then
  ok "ollama API at ${OLLAMA_URL}"
  if command -v python3 >/dev/null; then
    models=$(python3 -c 'import json; d=json.load(open("/tmp/linux-admin-ollama-tags.json")); print(",".join(m.get("name","") for m in d.get("models",[])))' 2>/dev/null || true)
    if [[ -n "${models}" ]]; then
      ok "ollama models: ${models}"
    else
      bad "ollama has no models pulled (run: ollama pull llama3.2:3b)"
    fi
  fi
else
  bad "ollama not reachable at ${OLLAMA_URL} (start: ollama serve)"
fi

# MCP package
if [[ -x "$ROOT/mcp/linux_admin/.venv/bin/linux-admin-mcp" ]]; then
  ok "linux-admin-mcp venv entrypoint"
else
  bad "linux-admin-mcp missing — run: scripts/bootstrap.sh"
fi

if command -v linux-admin-creds >/dev/null 2>&1; then
  ok "linux-admin-creds on PATH (venv)"
else
  warn "linux-admin-creds not on PATH (activate venv / re-bootstrap)"
fi

# Project config
if [[ -f "$ROOT/.grok/config.toml" ]]; then
  ok "project .grok/config.toml present"
else
  bad "missing .grok/config.toml"
fi

if [[ -f "$ROOT/AGENTS.md" ]]; then
  ok "AGENTS.md present"
else
  bad "missing AGENTS.md"
fi

# Quick tool smoke (no elevation)
if [[ -x "$ROOT/mcp/linux_admin/.venv/bin/python" ]]; then
  if "$ROOT/mcp/linux_admin/.venv/bin/python" -c '
from linux_admin_mcp.tools.resources import disk_df, host_identity
from linux_admin_mcp.tools.systemd import list_failed_units
h=host_identity(); d=disk_df(); f=list_failed_units()
assert "hostname" in h
assert d.get("returncode") == 0
print("tool_smoke_ok")
' 2>/tmp/linux-admin-tool-smoke.err; then
    ok "python tool smoke (disk/host/systemd)"
  else
    bad "python tool smoke failed (see /tmp/linux-admin-tool-smoke.err)"
    cat /tmp/linux-admin-tool-smoke.err >&2 || true
  fi
fi

# Creds status (non-secret)
if command -v linux-admin-creds >/dev/null 2>&1; then
  linux-admin-creds status >/tmp/linux-admin-creds-status.json 2>/dev/null || true
  if grep -qiE 'password|secret' /tmp/linux-admin-creds-status.json 2>/dev/null; then
    # has_sudo_password is ok; raw secret values are not
    if grep -qiE '"password"\s*:' /tmp/linux-admin-creds-status.json; then
      bad "creds status appears to include password field"
    else
      ok "creds status (no secret values)"
    fi
  else
    ok "creds status"
  fi
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "doctor: PASS"
  exit 0
else
  echo "doctor: FAIL"
  exit 1
fi
