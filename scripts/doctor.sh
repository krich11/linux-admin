#!/usr/bin/env bash
# Core path health check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${ROOT}/mcp/linux_admin/.venv/bin:${HOME}/.local/bin:${PATH}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

OLLAMA_URL="$OLLAMA_BASE_URL"
FAIL=0

ok() { printf '  [OK]  %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=1; }
warn() { printf '  [WARN] %s\n' "$*"; }

echo "== linux-admin doctor =="
echo "root: $ROOT"
echo "ollama: $OLLAMA_URL"

if command -v grok >/dev/null 2>&1; then
  ok "grok: $(command -v grok)"
else
  bad "grok not on PATH"
fi

if curl -sS --max-time 5 "${OLLAMA_URL}/api/tags" >/tmp/linux-admin-ollama-tags.json 2>/dev/null; then
  ok "ollama API at ${OLLAMA_URL}"
  if command -v python3 >/dev/null; then
    models=$(python3 -c 'import json; d=json.load(open("/tmp/linux-admin-ollama-tags.json")); print(",".join(m.get("name","") for m in d.get("models",[])[:12]))' 2>/dev/null || true)
    count=$(python3 -c 'import json; d=json.load(open("/tmp/linux-admin-ollama-tags.json")); print(len(d.get("models",[])))' 2>/dev/null || echo 0)
    if [[ "${count}" != "0" ]]; then
      ok "ollama models: ${count} total (sample: ${models}...)"
    else
      bad "ollama has no models"
    fi
    # ensure configured admin model exists
    if python3 -c "import json; d=json.load(open('/tmp/linux-admin-ollama-tags.json')); names={m.get('name') for m in d.get('models',[])}; import sys; sys.exit(0 if '${OLLAMA_ADMIN_MODEL}' in names or any('${OLLAMA_ADMIN_MODEL}'.split(':')[0] in (n or '') for n in names) else 1)"; then
      ok "admin model present on server: ${OLLAMA_ADMIN_MODEL}"
    else
      # exact match check
      if python3 -c "import json,sys; d=json.load(open('/tmp/linux-admin-ollama-tags.json')); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_ADMIN_MODEL}' in names else 1)"; then
        ok "admin model present: ${OLLAMA_ADMIN_MODEL}"
      else
        bad "admin model '${OLLAMA_ADMIN_MODEL}' not on server — pick another in config/ollama.env"
      fi
    fi
  fi
else
  bad "ollama not reachable at ${OLLAMA_URL}"
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

if grep -q '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" 2>/dev/null; then
  ok "user grok config has [model.ollama-admin]"
  if grep -A5 '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" | grep -q "$OLLAMA_BASE_URL\|192.168.200.120"; then
    ok "ollama-admin base_url points at configured Ollama host"
  else
    warn "ollama-admin base_url may be stale — run: scripts/install-user-models.sh"
    grep -A5 '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" | sed 's/^/         /'
  fi
else
  bad "missing [model.ollama-admin] in ~/.grok/config.toml (run: scripts/install-user-models.sh)"
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
