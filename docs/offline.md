# Offline / air-gap contract

## What “local” means here

- **Admin tools, credentials, skills, MCP:** run on this machine; no public internet required.
- **LLM inference (preferred):** LAN Ollama (`http://192.168.200.120:11434`).
- **LLM inference (fallback):** one small model on **this host** (`127.0.0.1:11434`, default `llama3.2:3b`) so you can still admin when the LAN Ollama is down.
- **Public internet** (npm registry, cloud LLMs, web search): not required for the core path; optional helpers must fail soft.

If the LAN host is down, `linux-admin` auto-switches to `ollama-local`. Keep that fallback warm with `linux-admin ensure-local`.

## Core path checklist

- Reachability of `OLLAMA_BASE_URL` on the LAN
- Grok `ollama-admin` model registered (`scripts/install-user-models.sh`)
- `linux-admin-mcp` from local venv
- Credentials + adaptive sudo
- In-repo skills / `AGENTS.md`

## Verify

```bash
./scripts/doctor.sh
./scripts/doctor-offline.sh
linux-admin -p "list failed systemd units and free disk"
```
