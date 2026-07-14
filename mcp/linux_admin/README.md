# linux-admin-mcp

Local-first MCP server for Linux host administration.

- Read-only tools: systemd, journal, disk, memory, network, packages
- Mutations: systemd start/stop/restart via adaptive sudo (`confirm=true`)
- Credentials: metadata only via MCP; secrets via `linux-admin-creds` CLI

## Run

```bash
# from repo after bootstrap
./mcp/linux_admin/.venv/bin/linux-admin-mcp
```

Configured from project `.grok/config.toml` as MCP server `linux-admin`.
