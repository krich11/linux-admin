# linux-admin

**Host administration agent** with a Grok-style TUI — **not** a generic coding session.

| Layer | What |
|-------|------|
| **Entry** | `linux-admin` → Grok with **admin agent + system prompt**, Ollama model, MCP |
| **LLM** | LAN Ollama (`ollama-admin`, T4-picked e.g. `qwen2.5:14b`) + local `ollama-local` |
| **Tools** | `linux-admin-mcp` (systemd, journal, disk, network, packages, creds) |
| **Identity** | `.grok/agents/linux-admin.md` + `linux-admin.system.md` |

## Quick start

```bash
./scripts/bootstrap.sh
linux-admin                          # admin TUI (banner + ollama model)
linux-admin -p "list failed units"
linux-admin doctor
linux-admin ensure-local            # break-glass local model
```

On launch you should see a **linux-admin banner** (host, model, LAN/local URLs) and the session should identify as host admin, not a coding project.

Switch models in TUI: `/model ollama-admin` · `ollama-local` · `ollama-fast`

## Layout

| Path | Purpose |
|------|---------|
| `scripts/linux-admin` | Product entry |
| `.grok/agents/linux-admin.md` | Agent definition |
| `.grok/agents/linux-admin.system.md` | System prompt override (identity) |
| `AGENTS.md` | Project rules |
| `mcp/linux_admin/` | MCP server |
| `config/ollama.env` | LAN + local Ollama endpoints |
| `skills/` | Admin runbooks |
| `docs/` | Offline, credentials, models |

## License

MIT — see [LICENSE](./LICENSE).
