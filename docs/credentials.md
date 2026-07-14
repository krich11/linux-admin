# Per-host credentials

Secrets live under `$XDG_DATA_HOME/linux-admin/hosts/<machine-id>/` (or the OS keyring). **Never commit secrets.**

## Commands

```bash
linux-admin creds init --policy auto --backend file
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
| `password` / askpass | Use stored secret only if `--allow-askpass` |
| `tty` | Interactive sudo |
| `manual` | Always hand off the command |

MCP tools only expose **status/metadata**, never password values.
