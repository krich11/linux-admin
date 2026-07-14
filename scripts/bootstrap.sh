#!/usr/bin/env bash
# Bootstrap: venv + Grok model registration. Does NOT install a local Ollama
# when a remote/LAN endpoint is configured (default: config/ollama.env).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/bin:${PATH}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

echo "== linux-admin bootstrap =="
echo "primary Ollama:  $OLLAMA_BASE_URL ($OLLAMA_ADMIN_MODEL)"
echo "local fallback:  $OLLAMA_LOCAL_BASE_URL ($OLLAMA_LOCAL_MODEL)"

if ! command -v uv >/dev/null 2>&1; then
  echo "installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
fi

echo "syncing linux-admin-mcp venv..."
cd "$ROOT/mcp/linux_admin"
uv venv --python 3.12 .venv 2>/dev/null || uv venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip install -e ".[dev]"
cd "$ROOT"

if curl -sS --max-time 5 "${OLLAMA_BASE_URL}/api/tags" >/tmp/linux-admin-bootstrap-tags.json 2>/dev/null; then
  echo "ollama reachable at ${OLLAMA_BASE_URL}"
  if ! python3 -c "import json,sys; d=json.load(open('/tmp/linux-admin-bootstrap-tags.json')); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_ADMIN_MODEL}' in names else 1)"; then
    echo "WARNING: ${OLLAMA_ADMIN_MODEL} not on remote server. Available sample:"
    python3 -c 'import json; d=json.load(open("/tmp/linux-admin-bootstrap-tags.json")); print("\n".join(m["name"] for m in d.get("models",[])[:20]))'
    echo "Edit config/ollama.env or pull the model on the Ollama host."
  fi
else
  echo "WARNING: cannot reach ${OLLAMA_BASE_URL} — fix network/Ollama host before using the agent."
fi

# Pick best T4-friendly model on LAN, register Grok endpoints, set session default once
"$ROOT/scripts/install-user-models.sh" --pick --set-default

# Break-glass local model (small) so admin works if LAN Ollama is down
"$ROOT/scripts/ensure-local-model.sh" || echo "WARNING: local fallback not ready — run later: linux-admin ensure-local"

if command -v linux-admin-creds >/dev/null 2>&1; then
  linux-admin-creds init --policy auto --backend file || true
fi

mkdir -p "${HOME}/.local/bin"
ln -sfn "$ROOT/scripts/linux-admin" "${HOME}/.local/bin/linux-admin"
chmod +x "$ROOT/scripts/"*.sh "$ROOT/scripts/linux-admin" "$ROOT/scripts/linux-admin-askpass" 2>/dev/null || true

echo
echo "bootstrap complete."
echo "  interactive:  linux-admin"
echo "  headless:     linux-admin -p \"list failed units\""
echo "  doctor:       linux-admin doctor"
"$ROOT/scripts/doctor.sh" || true
