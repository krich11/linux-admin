#!/usr/bin/env bash
# Core path health check (primary LAN + local fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${ROOT}/mcp/linux_admin/.venv/bin:${HOME}/.local/bin:${PATH}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

FAIL=0
PRIMARY_OK=0
LOCAL_OK=0

ok() { printf '  [OK]  %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=1; }
warn() { printf '  [WARN] %s\n' "$*"; }

echo "== linux-admin doctor =="
echo "root:     $ROOT"
echo "primary:  $OLLAMA_BASE_URL  ($OLLAMA_ADMIN_MODEL)"
echo "local:    $OLLAMA_LOCAL_BASE_URL  ($OLLAMA_LOCAL_MODEL)"

if command -v grok >/dev/null 2>&1; then
  ok "grok: $(command -v grok)"
else
  bad "grok not on PATH"
fi

# --- Primary (LAN) ---
if curl -sS --max-time 5 "${OLLAMA_BASE_URL}/api/tags" >/tmp/linux-admin-ollama-primary.json 2>/dev/null; then
  PRIMARY_OK=1
  count=$(python3 -c 'import json; d=json.load(open("/tmp/linux-admin-ollama-primary.json")); print(len(d.get("models",[])))' 2>/dev/null || echo 0)
  ok "primary Ollama up (${count} models)"
  if python3 -c "import json,sys; d=json.load(open('/tmp/linux-admin-ollama-primary.json')); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_ADMIN_MODEL}' in names else 1)"; then
    ok "primary has admin model: ${OLLAMA_ADMIN_MODEL}"
  else
    warn "primary missing ${OLLAMA_ADMIN_MODEL} — edit config/ollama.env"
  fi
else
  warn "primary Ollama unreachable at ${OLLAMA_BASE_URL} (will use local if available)"
fi

# --- Local fallback ---
if curl -sS --max-time 3 "${OLLAMA_LOCAL_BASE_URL}/api/tags" >/tmp/linux-admin-ollama-local.json 2>/dev/null; then
  if python3 -c "import json,sys; d=json.load(open('/tmp/linux-admin-ollama-local.json')); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_LOCAL_MODEL}' in names else 1)"; then
    LOCAL_OK=1
    ok "local fallback ready: ${OLLAMA_LOCAL_MODEL} @ ${OLLAMA_LOCAL_BASE_URL}"
  else
    warn "local Ollama up but missing ${OLLAMA_LOCAL_MODEL} — run: linux-admin ensure-local"
  fi
else
  warn "local Ollama not reachable at ${OLLAMA_LOCAL_BASE_URL} — run: linux-admin ensure-local"
fi

if [[ "$PRIMARY_OK" -eq 0 && "$LOCAL_OK" -eq 0 ]]; then
  bad "no usable Ollama path (primary and local both unavailable)"
else
  sel="$(select_grok_model 2>/dev/null || true)"
  ok "auto-selected Grok model id: ${sel:-unknown}"
fi

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

if [[ -f "$ROOT/.grok/config.toml" ]]; then
  ok "project .grok/config.toml present"
else
  bad "missing .grok/config.toml"
fi

if grep -q '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" 2>/dev/null \
  && grep -q '\[model\.ollama-local\]' "${HOME}/.grok/config.toml" 2>/dev/null; then
  ok "user grok config has ollama-admin + ollama-local"
else
  bad "missing model entries — run: scripts/install-user-models.sh"
fi

if [[ -f "$ROOT/AGENTS.md" ]]; then
  ok "AGENTS.md present"
else
  bad "missing AGENTS.md"
fi

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

if command -v linux-admin-creds >/dev/null 2>&1; then
  linux-admin-creds status >/tmp/linux-admin-creds-status.json 2>/dev/null || true
  if grep -qiE '"password"\s*:' /tmp/linux-admin-creds-status.json 2>/dev/null; then
    bad "creds status appears to include password field"
  else
    ok "creds status (no secret values)"
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
