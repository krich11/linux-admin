# Offline / air-gap contract

## Core path (must work with WAN down)

- Ollama on `127.0.0.1:11434` with models already pulled
- Grok using project models (`ollama-admin`)
- `linux-admin-mcp` from local venv (no `npx -y`)
- Credentials + adaptive sudo
- In-repo skills and `AGENTS.md`

## Optional online layer

Web search, CVE fetch, remote MCP, `apt update` against mirrors, `docker pull`, etc. may be unavailable. That is expected. They must:

- fail fast
- not block session start
- not be required for skill success

## Verify

```bash
./scripts/doctor.sh
./scripts/doctor-offline.sh
# optional airplane mode:
#   sudo ip route del default
#   ./scripts/doctor-offline.sh
#   linux-admin -p "list failed systemd units and free disk"
# restore default route afterward
```
