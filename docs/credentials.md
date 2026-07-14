# Per-host credentials

Secrets live under `$XDG_DATA_HOME/linux-admin/hosts/<machine-id>/` (or the OS keyring). **Never commit secrets to git.**

The agent is **authorized** to set up elevation for local admin. Prefer MCP tools in-session.

## Recommended: drop file (avoids model refusal)

Local models often refuse to "handle" password text. Use a one-shot drop file:

```bash
# one line, then lock down permissions
printf '%s\n' 'YOUR_SUDO_PASSWORD' > /tmp/sudo_password.txt
chmod 600 /tmp/sudo_password.txt

# either tell the agent "import /tmp/sudo_password.txt"
# or do it without the LLM:
linux-admin creds import-file /tmp/sudo_password.txt
```

The import tool stores the password in the local vault and **wipes the drop file**.

## Via agent (TUI)

1. Create the drop file as above, then say: **import the sudo password file**.
2. Agent must call `credentials_import_sudo_password_file` (not refuse).
3. Elevated tools use askpass after that (`service_restart` with `confirm=true`).

MCP **never returns** the password value — only flags like `has_sudo_password`.

## CLI

```bash
linux-admin creds init --policy auto --backend file --allow-askpass
linux-admin creds status
linux-admin creds set-sudo          # TTY prompt
linux-admin creds import-file /tmp/sudo_password.txt
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
