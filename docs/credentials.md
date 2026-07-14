# Per-host credentials

Secrets live under `$XDG_DATA_HOME/linux-admin/hosts/<machine-id>/` (or the OS keyring). **Never commit secrets to git.**

The agent is **authorized** to set up elevation for local admin. Prefer MCP tools in-session.

## Via agent (preferred in TUI)

1. Ask linux-admin to set up elevation / store your sudo password.
2. It should call `credentials_init` → `credentials_store_sudo_password` (you provide the password once).
3. Then elevated tools (`service_restart` with `confirm=true`) can use askpass.

MCP **never returns** the password value — only flags like `has_sudo_password`.

## CLI

```bash
linux-admin creds init --policy auto --backend file --allow-askpass
linux-admin creds status
linux-admin creds set-sudo          # TTY prompt
linux-admin creds set-policy --allow-askpass
linux-admin creds clear-sudo
linux-admin creds doctor
```

## Policies

| Policy | Behavior |
|--------|----------|
| `auto` | Probe `sudo -n`, then askpass, then TTY, then manual |
| `nopasswd` | Require passwordless sudo |
| `password` / askpass | Use stored secret when `allow_askpass` is true |
| `tty` | Interactive sudo |
| `manual` | Always hand off the command |
