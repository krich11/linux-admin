# linux-admin

**Fully local** Linux administration agent:

- **Grok CLI** as the agent host (tools, permissions, sessions, ACP)
- **Ollama only** for LLM inference (`http://127.0.0.1:11434/v1`)
- **Local MCP servers** launched from vendored / lockfile-installed binaries on disk

## Offline requirement

This project must run at **full capacity with no internet**. Software may be downloaded during bootstrap (Ollama, model weights, apt packages, locked npm/uv deps). After that, inference, tools, skills, and MCP must not depend on WAN reachability.

There is **no cloud LLM fallback** in the project profile.

Details: **[PLAN.md](./PLAN.md)** (§1.1 Offline-first constraint).

## Status

Planning. Architecture, MCP inventory, offline contract, and PR breakdown are in `PLAN.md`.

## Intent

```
You → Grok (this repo) → Ollama (loopback, local weights)
                       → MCP (stdio, vendored entrypoints)
                       → Ubuntu host (inspect → plan → apply → verify)

No required path: public internet, cloud APIs, npx -y, live registries
```

## Prerequisites (high level)

1. Ubuntu (developed against 24.04)
2. Grok CLI installed on disk
3. Ollama installed, models **already pulled**, serving on `127.0.0.1:11434`
4. Bootstrap completed once online (`scripts/bootstrap.sh` — forthcoming) so MCP deps exist under `vendor/` / `.venv`

## Repository

GitHub: [krich11/linux-admin](https://github.com/krich11/linux-admin)  
(GitHub is for source distribution only — not a runtime dependency.)

## License

TBD in follow-up (default leaning MIT unless noted otherwise).
