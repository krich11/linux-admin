#!/usr/bin/env bash
# Assert CORE path does not require public internet.
# LAN Ollama (config/ollama.env) is part of the intended core path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${ROOT}/mcp/linux_admin/.venv/bin:${HOME}/.local/bin:${PATH}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

echo "== linux-admin doctor-offline (core path) =="
echo "ollama (LAN OK): $OLLAMA_BASE_URL"

"$ROOT/scripts/doctor.sh"

if grep -R --include='config.toml' -E '^\s*(command|args)\s*=' "$ROOT/.grok" 2>/dev/null \
  | grep -E 'npx|uvx' \
  | grep -vE '^\s*#' ; then
  if grep -R --include='config.toml' -E 'npx[^\n]*-y|command\s*=\s*"uvx"|command\s*=\s*\x27uvx\x27' "$ROOT/.grok" 2>/dev/null \
    | grep -vE '^\s*#|/#|comment' ; then
    echo "  [FAIL] project config appears to use runtime registry installers (npx -y / uvx)"
    exit 1
  fi
fi
echo "  [OK]  no npx -y / uvx runtime installers in project MCP commands"

if grep -A6 '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" 2>/dev/null | grep -q 'base_url'; then
  if grep -A6 '\[model\.ollama-admin\]' "${HOME}/.grok/config.toml" | grep -E 'openai\.com|api\.x\.ai|anthropic\.com'; then
    echo "  [FAIL] ollama-admin base_url looks like a public cloud API"
    exit 1
  fi
  echo "  [OK]  model base_url is not a public cloud LLM API"
else
  echo "  [WARN] could not inspect ollama-admin base_url"
fi

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

# Remote/LAN Ollama generate smoke
if curl -sS --max-time 5 "${OLLAMA_BASE_URL}/api/tags" >/tmp/oa.json 2>/dev/null; then
  if curl -sS --max-time 120 "${OLLAMA_BASE_URL}/api/generate" \
    -d "{\"model\":\"${OLLAMA_ADMIN_MODEL}\",\"prompt\":\"Reply with exactly: pong\",\"stream\":false}" \
    2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("response","")[:120])' \
    | grep -qi pong; then
    echo "  [OK]  ollama generate via ${OLLAMA_BASE_URL} (${OLLAMA_ADMIN_MODEL})"
  else
    echo "  [WARN] generate smoke inconclusive for ${OLLAMA_ADMIN_MODEL} (server reachable)"
  fi
fi

echo
echo "doctor-offline: PASS (core path; LAN Ollama allowed)"
exit 0
