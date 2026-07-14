# linux-admin

Local-first **Linux administration agent** built around:

- **Grok CLI** as the agent host (tools, permissions, sessions, ACP)
- **Ollama** for local LLM inference (`http://127.0.0.1:11434/v1`)
- **Local MCP servers** for safe, scoped host operations

## Status

Planning complete. See **[PLAN.md](./PLAN.md)** for architecture, MCP inventory, security posture, phases, and PR breakdown.

## Quick intent

```
You → Grok (this repo) → Ollama models
                       → MCP: filesystem, custom linux-admin tools, …
                       → Ubuntu host (inspect → plan → apply → verify)
```

## Prerequisites (high level)

1. Ubuntu (developed against 24.04)
2. [Grok CLI](https://x.ai) configured
3. [Ollama](https://ollama.com) installed and serving on port `11434`
4. Node/`npx` for reference MCP packages; `uv` recommended for the custom Python MCP server

Bootstrap scripts and project config land in later PRs per the plan.

## Repository

GitHub: [krich11/linux-admin](https://github.com/krich11/linux-admin)

## License

TBD in follow-up (default leaning MIT unless noted otherwise).
