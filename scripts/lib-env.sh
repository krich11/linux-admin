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
# Strip trailing slash
OLLAMA_BASE_URL="${OLLAMA_BASE_URL%/}"
OLLAMA_OPENAI_BASE="${OLLAMA_BASE_URL}/v1"
