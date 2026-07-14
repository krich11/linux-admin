#!/usr/bin/env bash
# Ensure local Ollama is up and has the break-glass model pulled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib-env.sh"

echo "== ensure local Ollama fallback =="
echo "local URL:  $OLLAMA_LOCAL_BASE_URL"
echo "local model: $OLLAMA_LOCAL_MODEL"

start_local_ollama() {
  if curl -sS --max-time 2 "${OLLAMA_LOCAL_BASE_URL}/api/tags" >/dev/null 2>&1; then
    return 0
  fi
  if systemctl is-enabled ollama >/dev/null 2>&1; then
    echo "starting system ollama.service..."
    sudo systemctl start ollama 2>/dev/null || true
    sleep 2
  fi
  if curl -sS --max-time 2 "${OLLAMA_LOCAL_BASE_URL}/api/tags" >/dev/null 2>&1; then
    return 0
  fi
  if command -v ollama >/dev/null 2>&1; then
    echo "starting user ollama serve in background..."
    nohup ollama serve >/tmp/linux-admin-ollama-local.log 2>&1 &
    sleep 2
  fi
  curl -sS --max-time 3 "${OLLAMA_LOCAL_BASE_URL}/api/tags" >/dev/null 2>&1
}

if ! start_local_ollama; then
  echo "ERROR: cannot reach local Ollama at ${OLLAMA_LOCAL_BASE_URL}" >&2
  exit 1
fi
echo "local Ollama is up"

# Does the local server already have the model?
if curl -sS --max-time 5 "${OLLAMA_LOCAL_BASE_URL}/api/tags" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_LOCAL_MODEL}' in names else 1)"; then
  echo "local model already present: ${OLLAMA_LOCAL_MODEL}"
  exit 0
fi

echo "pulling local fallback model on this host: ${OLLAMA_LOCAL_MODEL}"
echo "(stores on the local Ollama server library — not in the git repo)"
# Prefer API pull against local host
export OLLAMA_HOST="${OLLAMA_LOCAL_BASE_URL#http://}"
export OLLAMA_HOST="${OLLAMA_HOST#https://}"
if command -v ollama >/dev/null 2>&1; then
  ollama pull "${OLLAMA_LOCAL_MODEL}"
else
  echo "ERROR: ollama CLI not found; install Ollama on this host for fallback" >&2
  exit 1
fi

if curl -sS --max-time 5 "${OLLAMA_LOCAL_BASE_URL}/api/tags" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); names={m.get('name') for m in d.get('models',[])}; sys.exit(0 if '${OLLAMA_LOCAL_MODEL}' in names else 1)"; then
  echo "local fallback ready: ${OLLAMA_LOCAL_MODEL}"
  exit 0
fi
echo "ERROR: pull finished but model not listed" >&2
exit 1
