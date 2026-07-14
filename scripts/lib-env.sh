#!/usr/bin/env bash
# Source shared env for linux-admin scripts.
# shellcheck disable=SC1091
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/config/ollama.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/config/ollama.env"
fi

OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://192.168.200.120:11434}"
OLLAMA_ADMIN_MODEL="${OLLAMA_ADMIN_MODEL:-qwen2.5-coder:7b}"
OLLAMA_FAST_MODEL="${OLLAMA_FAST_MODEL:-llama3.2:3b}"
OLLAMA_LOCAL_BASE_URL="${OLLAMA_LOCAL_BASE_URL:-http://127.0.0.1:11434}"
OLLAMA_LOCAL_MODEL="${OLLAMA_LOCAL_MODEL:-llama3.2:3b}"

# Strip trailing slashes
OLLAMA_BASE_URL="${OLLAMA_BASE_URL%/}"
OLLAMA_LOCAL_BASE_URL="${OLLAMA_LOCAL_BASE_URL%/}"
OLLAMA_OPENAI_BASE="${OLLAMA_BASE_URL}/v1"
OLLAMA_LOCAL_OPENAI_BASE="${OLLAMA_LOCAL_BASE_URL}/v1"

ollama_reachable() {
  local url="${1:?url}"
  curl -sS --max-time 2 "${url}/api/tags" >/dev/null 2>&1
}

# Echo selected Grok model id: ollama-admin | ollama-local
# Respect LINUX_ADMIN_MODEL if already set to a concrete id.
select_grok_model() {
  if [[ -n "${LINUX_ADMIN_MODEL:-}" ]]; then
    printf '%s\n' "$LINUX_ADMIN_MODEL"
    return 0
  fi
  if ollama_reachable "$OLLAMA_BASE_URL"; then
    printf 'ollama-admin\n'
    return 0
  fi
  if ollama_reachable "$OLLAMA_LOCAL_BASE_URL"; then
    echo "linux-admin: primary Ollama unreachable ($OLLAMA_BASE_URL); using local fallback ($OLLAMA_LOCAL_BASE_URL / $OLLAMA_LOCAL_MODEL)" >&2
    printf 'ollama-local\n'
    return 0
  fi
  echo "linux-admin: neither primary nor local Ollama is reachable" >&2
  echo "  primary: $OLLAMA_BASE_URL" >&2
  echo "  local:   $OLLAMA_LOCAL_BASE_URL" >&2
  printf 'ollama-local\n' # still prefer local id for clearer errors
  return 1
}
