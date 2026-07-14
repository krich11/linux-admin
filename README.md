# linux-admin

**Local-first** Linux administration agent with a **Grok-style CLI**.

- **UI:** `linux-admin` → Grok TUI (scrollback, prompt, tools, approvals)
- **LLM:** Ollama on `127.0.0.1:11434` (default model `llama3.2:3b`)
- **Tools:** `linux-admin-mcp` (systemd, journal, disk, network, packages, …)
- **Creds / sudo:** per-host store + adaptive elevation (NOPASSWD, askpass, TTY, manual)
- **Offline core path:** full local admin without WAN; optional online helpers must not block

## Quick start

```bash
# once (needs network for install/pull)
./scripts/bootstrap.sh

# interactive Grok-style session
linux-admin

# headless
linux-admin -p "List failed systemd units and free disk space"

# health
linux-admin doctor
linux-admin doctor-offline

# credentials (never pass passwords on argv)
linux-admin creds init
linux-admin creds set-sudo
linux-admin creds set-policy --allow-askpass
linux-admin creds doctor
```

## Layout

| Path | Purpose |
|------|---------|
| `scripts/linux-admin` | Primary CLI entry |
| `.grok/config.toml` | Ollama models + MCP wiring |
| `AGENTS.md` | Agent operating rules |
| `mcp/linux_admin/` | Custom MCP server + elevate/creds |
| `skills/` | Local admin runbooks |
| `docs/` | Offline, credentials, security, models |
| `PLAN.md` | Full design |

## Offline contract

See [docs/offline.md](./docs/offline.md). Core path must work with no internet after bootstrap. Search/CVE/etc. may be unavailable and must fail soft.

## License

MIT — see [LICENSE](./LICENSE).
