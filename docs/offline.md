# Offline / air-gap contract

## What “local” means here

- **Admin tools, credentials, skills, MCP:** run on this machine; no public internet required.
- **LLM inference:** your **LAN Ollama** (`config/ollama.env`, default `http://192.168.200.120:11434`). Models live on that host’s Ollama library.
- **Public internet** (npm registry, cloud LLMs, web search): not required for the core path; optional helpers must fail soft.

If the LAN Ollama host is down, the agent cannot reason — same as any remote dependency — but you do **not** need the public internet.

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
