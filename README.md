# linux-admin

**Local-first** Linux administration agent with a **Grok-style CLI** (TUI chat + tools — not a web UI):

- **Interface:** Grok TUI via a `linux-admin` launcher (scrollback, prompt, streamed tools, approvals)
- **Harness:** Grok CLI / ACP (local process)
- **Ollama** for required LLM inference (`http://127.0.0.1:11434/v1`)
- **Local MCP servers** launched from vendored / lockfile-installed binaries on disk
- **Per-host credential repository** (OS keyring or encrypted local store — never git)
- **Adaptive sudo** for hosts that need a password, NOPASSWD, a cached ticket, a TTY prompt, or a manual handoff
- **Optional online helpers** (search, docs fetch, etc.) when the network is up — never required for local admin

## Offline / air-gap contract

**Core path must work at full local capacity with no internet** after bootstrap: Ollama, credentials, sudo, skills, and admin tools.

Some resources are inherently online-only (internet search, remote CVE/docs, upstream mirrors). Those are fine as **optional enrichment**. They must:

- fail fast and clearly when unreachable  
- not block session start  
- not be required steps in core admin skills  

There is **no cloud LLM requirement** for this project’s default profile.

Details: **[PLAN.md](./PLAN.md)** (§1.1, §6).

## Status

Planning. Architecture, MCP inventory, offline contract, credentials/sudo, and PR breakdown are in `PLAN.md`.

## Intent

```
You (CLI) → linux-admin → Grok TUI (Grok-style interface)
                        → Ollama (loopback, local weights)     [CORE]
                        → MCP admin tools (vendored)           [CORE]
                        → credential store + sudo runner       [CORE]
                        → Ubuntu host (inspect → plan → apply → verify)

                     ↘ optional: search / fetch / remotes      [ONLINE]
                       (enrichment only; soft-fail offline)

Headless: linux-admin -p "…"
Secrets never go to the LLM or to git
```

## Interface (planned)

| Mode | Command (planned) | Experience |
|------|-------------------|------------|
| Interactive | `linux-admin` | Full Grok-style TUI in this project |
| Headless | `linux-admin -p "…"` | One-shot / scripts / cron |
| Utilities | `linux-admin creds|doctor|…` | Non-chat ops |

We reuse Grok’s TUI rather than building a separate web or custom terminal framework.

## Prerequisites (high level)

1. Ubuntu (developed against 24.04)
2. Grok CLI installed on disk
3. Ollama installed, models **already pulled**, serving on `127.0.0.1:11434`
4. Bootstrap completed once online (`scripts/bootstrap.sh` — forthcoming) so MCP deps exist under `vendor/` / `.venv`

## Repository

GitHub: [krich11/linux-admin](https://github.com/krich11/linux-admin)  
(GitHub is for source distribution only — not a runtime dependency of the core path.)

## License

TBD in follow-up (default leaning MIT unless noted otherwise).
