# Linux Admin Agent — Implementation Plan

**Status:** Planning  
**Owner:** krich11  
**Host:** Ubuntu 24.04 LTS (`phoenix`)  
**Agent harness:** Grok CLI / ACP (local process only)  
**Primary UI:** **Grok-style CLI TUI** (see §1.2) — not a web UI  
**LLM backend:** Ollama (`http://127.0.0.1:11434/v1`) for the core path  
**Repo:** `krich11/linux-admin`  
**Hard constraint:** **Core admin path is 100% offline-capable** (see §1.1). Optional online helpers are allowed if they never block that path.

---

## 1. Goals

Build a **local-first Linux administration agent** that:

1. **Runs at full local capacity with no internet.** Core inference, elevation, credentials, skills, and admin MCP tools must work with the WAN down.
2. Uses **Ollama** as the **required** inference backend for this project (no cloud model required for the agent to work).
3. Exposes safe, scoped **local MCP servers** for filesystem, process/service control, packages, logs, network diagnostics, containers, and git — all launched from **pre-installed, vendored, or lockfile-resolved** binaries on disk.
4. Encodes admin workflow knowledge as **project rules + skills** (shipped in-repo) so the agent prefers inspect → plan → apply → verify over blind shell.
5. Defaults to **least privilege** and explicit confirmation for destructive actions.
6. Maintains a **per-host credential repository** (local, never git) and **flexible sudo elevation** that works whether the host requires a password, uses NOPASSWD, has a valid sudo timestamp, or needs a human at a TTY.
7. May offer **optional online enrichment** (web search, CVE lookup, docs fetch, etc.) when the network is available — without making those services necessary for startup or for local admin work.

### 1.1 Offline-first constraint (non-negotiable for the core path)

**Intent (clarified):** Air-gapped / offline operation must deliver full **local admin** capability. It is expected that some resources are simply not available offline (internet search, remote CVE databases, upstream package mirrors, cloud APIs). Those features are fine to ship as **optional enhancements**. They must **fail soft** and must **not interfere** with fully local operation.

```
┌─────────────────────────────────────────────────────────────┐
│  CORE PATH (must work with WAN down)                        │
│  Ollama · vendored local MCP · creds · sudo · skills/docs   │
│  diagnose / stage / apply / verify on this host             │
└─────────────────────────────────────────────────────────────┘
        ▲ must never depend on ▼
┌─────────────────────────────────────────────────────────────┐
│  OPTIONAL ONLINE LAYER (nice-to-have when reachable)        │
│  web search · CVE/docs fetch · remote MCP · git push/fetch  │
│  apt against remote mirrors · image pulls · etc.            │
│  → timeout fast · clear "unavailable offline" · continue    │
└─────────────────────────────────────────────────────────────┘
```

#### Rules

| Rule | Meaning |
|------|---------|
| **No required WAN** | Nothing on the core path may *require* public internet success to start, load tools, run inference, elevate, or complete local admin workflows. |
| **Optional is optional** | Online-only tools/MCP servers may exist; they are disabled by default in the strict offline profile, or enabled but treated as best-effort. |
| **Fail soft** | If search/fetch/mirror/remote MCP is down or unreachable: return a structured “unavailable” result, do not hang, do not crash the agent, do not block other tools. |
| **Skills stay local-first** | Core skill steps use local state and in-repo runbooks. Online lookup may be an *extra* step (“if network available, optionally…”), never a required step for success criteria. |
| **Startup isolation** | Session start must not block on optional MCP that needs the network (`npx -y`, remote HTTP MCP health, model pull, etc.). Core MCP is vendored/local. |
| **Inference** | Default model is Ollama on loopback. Cloud models may exist in a *separate* personal Grok config; they must not be required by this project’s default profile. |

| Core (offline OK) | Optional online (may be absent) |
|-------------------|----------------------------------|
| Ollama inference from local weights | Web search, CVE/advisory lookup |
| Vendored filesystem / git / memory / `linux-admin-mcp` | HTTP `fetch` MCP, remote docs portals |
| Per-host credentials + adaptive sudo | Cloud secret managers |
| In-repo skills + local man pages | “Search the web for this error” |
| Local dpkg/apt cache, journal, systemd | `apt update` against remote mirrors |
| Local Docker socket inspect (no pull) | `docker pull`, registry auth |
| Bootstrap once while online | Runtime registry installs (`npx -y`, live `uvx`) |

**Definition of done for offline:** With the host’s default route removed or WAN unplugged, after bootstrap has already completed:

1. Ollama serves the configured model(s) from local disk.
2. Grok starts and can use core local MCP without waiting on online services.
3. Full diagnose / stage / apply / verify loops work for **local** admin tasks (services, journals, disks, local networking, local package DB / cache operations).
4. Optional online tools, if configured, either are not loaded or fail quickly with a clear error — they do not break the session.
5. `scripts/doctor.sh` and `scripts/doctor-offline.sh` both pass (**doctor-offline asserts the core path only**).

**Bootstrap vs runtime**

```
[Bootstrap — internet OK]          [Runtime — internet optional / absent]
 install Ollama, pull models   →   ollama serve (local weights)
 uv sync / npm ci into vendor  →   node/python entrypoints from vendor/
 apt install host packages     →   systemctl, journalctl, dpkg, …
 clone/pull this repo          →   AGENTS.md, skills/, docs/ on disk
 optional: configure search MCP →  used only when WAN up; ignored offline
```

### Non-goals (v1)

- Multi-host orchestration / fleet management (Ansible replacement). Per-host credential *stores* are local to each machine; there is no central secret server in v1.
- Unattended root automation across the network.
- Requiring cloud LLM inference for this project’s default profile.
- Building a full custom agent runtime from scratch (reuse Grok as the tool-using agent host **in offline mode**).
- Making online-only features (search, CVE, etc.) **mandatory** for admin workflows.
- Depending on GitHub, npm registry, PyPI, or model hubs **after first setup** for the core path.
- Putting sudo passwords, API tokens, or private keys in the git repository or in LLM prompts/logs.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Operator (TUI / headless / ACP IDE)                             │
│  All paths: local process only                                   │
└────────────────────────────┬─────────────────────────────────────┘
                             │ prompts / approvals
┌────────────────────────────▼─────────────────────────────────────┐
│  Grok agent (this repo as cwd)                                   │
│  • default model = ollama-* (required core path)                 │
│  • AGENTS.md / .grok project config                              │
│  • Skills + in-repo runbooks (local-first; online optional)      │
│  • Permission policy (read-heavy; write gated)                   │
│  • Core MCP always local; optional online MCP never blocks start │
└───────┬───────────────────────────────┬──────────────────────────┘
        │ loopback (core)               │ stdio (core local MCP)
        ▼                               ▼
┌───────────────────┐     ┌────────────────────────────────────────┐
│ Ollama (required) │     │ CORE MCP (vendored; offline OK)        │
│ 127.0.0.1:11434   │     │  filesystem | git | memory             │
│ weights on disk   │     │  linux-admin (systemd/journal/…)       │
└───────────────────┘     │  docker* local socket (no pull req.)   │
                          └───────────────┬────────────────────────┘
        ┌─────────────────────────────────┤
        │ optional, fail-soft             │ elevate via sudo policy
        ▼                                 ▼
┌───────────────────┐     ┌────────────────────────────────────────┐
│ ONLINE MCP/tools  │     │ Per-host credential repository         │
│ search, fetch, …  │     │  XDG / keyring — never git / LLM       │
│ (WAN if present)  │     └─────────────────────┬──────────────────┘
└───────────────────┘                           ▼
                      Host OS (Ubuntu 24.04)
                      systemctl, apt/dpkg, journalctl, ip, ss, …
                      sudo (NOPASSWD | password | cached ticket)
                      core path: no egress required
```

### Why Grok + Ollama + MCP (under offline constraint)

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Agent host | Grok CLI **with project model override** | Local process; must be configured so sessions never call xAI for this repo |
| Models | Ollama on loopback | Weights and inference stay on host; Grok custom `base_url` |
| Tools | Local stdio MCP from **vendor/** or locked venv | No registry hits at startup; portable tool boundary |
| Knowledge | In-repo skills + docs first | Online search/docs optional enrichment only |
| Policy | Project rules + permission modes | High blast radius; conservative defaults |
| Secrets | Per-host credential repo (XDG / keyring) | Offline, machine-scoped; not in git or model context |
| Elevation | Adaptive sudo (see §6) | Hosts differ: password, NOPASSWD, ticket, or human TTY |
| Online extras | Optional MCP/tools, fail soft | Must not gate core path or doctor-offline |

### Grok core-path checklist

Project config must ensure:

1. `[models] default` is an Ollama model id (core path does not need cloud inference).
2. Core `[model.*]` entries used by default point at `http://127.0.0.1:11434/v1`.
3. No secondary/fallback model **required** for this workspace points only at the cloud (optional cloud models are fine if unused when offline).
4. **Core** MCP servers are vendored/local and start without network. Optional online MCP (search, fetch, remote GitHub, etc.) must not block session start if unreachable — prefer `enabled = false` by default or short timeouts + non-fatal doctor checks.
5. If Grok itself phones home for auth/telemetry, document it; prefer modes that work with local models without live xAI session **if the CLI supports that**. Validate during Phase 1; if a signed-in cloud session is required just to start the binary, treat that as a **core-path blocker**.

---

## 3. Prerequisites

### 3.1 Host tools (already largely present)

- Ubuntu 24.04, `systemctl`, `journalctl`, `python3`
- Node 22 (for vendoring JS MCP servers **at bootstrap**, not via live `npx -y` each run)
- Grok CLI installed **on disk** under `~/.grok` / PATH
- Optional: `uv` for Python MCP packaging (bootstrap install, then offline `uv run --frozen` / venv)

### 3.2 Ollama (required — currently not listening on this host)

At plan time, nothing answered on `127.0.0.1:11434`. Install, pull models, and **verify offline inference** before calling Phase 1 done:

```bash
# --- Bootstrap (internet OK) ---
curl -fsSL https://ollama.com/install.sh | sh   # or offline .deb if air-gapped later
sudo systemctl enable --now ollama

ollama pull qwen2.5-coder:14b
ollama pull llama3.1:8b
# Record digests/tags in docs/ollama-models.md

# --- Runtime checks (must work with WAN down) ---
curl -s http://127.0.0.1:11434/api/tags
# optional: unplug WAN / ip route del default, then:
ollama run qwen2.5-coder:14b "Reply with exactly: pong"
```

**Hardware note:** Pick default model size from available VRAM/RAM. Document in `docs/ollama-models.md`. Never configure a model tag that is not already present locally (`ollama list`).

### 3.3 Dependency vendoring (required for offline MCP)

| Kind | Bootstrap (online) | Runtime (offline) |
|------|--------------------|-------------------|
| Python MCP | `uv sync --frozen` into project `.venv` or locked env | ` .venv/bin/linux-admin-mcp` or `uv run --offline --frozen` |
| JS MCP (filesystem, git, memory) | `npm ci` into `vendor/mcp/<name>/` with package-lock | `node vendor/mcp/filesystem/dist/...` or `npx --offline` from that tree — **never** `npx -y @scope/pkg` without local cache |
| Host packages | `apt-get install …` while online | Use installed binaries only |
| Ollama models | `ollama pull` while online | Serve from local blob store only |

Pin versions in lockfiles committed to the repo (`uv.lock`, `package-lock.json`). Prefer committing enough lock + install scripts that a second machine can bootstrap once online, then stay offline.

### 3.4 Optional tools

| Tool | Use | Offline note |
|------|-----|----------------|
| Docker / Podman | Container admin | Local socket only; **no** image pulls in default skills |
| `smartmontools`, `lm-sensors` | Hardware health | Install at bootstrap |
| `fail2ban`, `ufw` | Security skills | Local state only |
| Local apt mirror / `apt-offline` | Package work without WAN | Optional ops enhancement; agent must degrade gracefully if mirrors unreachable |

---

## 4. Local MCP server inventory

Prefer **project-scoped** config in `.grok/config.toml`. Every MCP command must resolve to a **local filesystem path** that exists after bootstrap.

### 4.1 Tier A — MVP (Phase 1)

| Server name | Source | Purpose | Offline / safety |
|-------------|--------|---------|------------------|
| `filesystem` | Vendored `@modelcontextprotocol/server-filesystem` | Allowlisted file R/W | No network; tight path allowlist |
| `git` | Vendored git MCP **or** thin wrappers in `linux-admin-mcp` | Local repo inspect/commit | No `git fetch`/`push` in default tools |
| `memory` | Vendored memory MCP **or** local JSON under `.linux-admin/memory/` | Persist host facts | Disk only |

**Optional online MCP (Tier A+ / not on core path):** e.g. `fetch`, web search, remote docs. Allowed when the operator wants enrichment. Requirements: (1) not required for any core skill success criterion; (2) short timeouts; (3) clean “network unavailable” errors; (4) disabled in the default offline profile or omitted from `doctor-offline` success conditions; (5) must not use `npx -y` at session start without a local cache.

**Filesystem allowlist (recommended MVP):**

```
read:  /etc, /var/log, /usr/lib/systemd, /lib/systemd, /proc, /sys (limited), project root
write: project root, /tmp/linux-admin-staging, optional ~/admin-work
```

Destructive host edits (`/etc` write) go through a **staged patch workflow** (§6), not unrestricted MCP write in v1.

### 4.2 Tier B — Admin-specific (Phase 2, custom MCP)

Build **`linux-admin-mcp`** in-repo (Python + uv recommended):

| Tool groups | Example tools | Offline notes |
|-------------|---------------|---------------|
| **Systemd** | `service_status`, `service_logs`, `service_restart`, `list_failed_units` | Local dbus/systemctl only |
| **Journal** | `journal_query`, `journal_since`, `boot_errors` | Local journald |
| **Packages** | `apt_list_upgradable`, `dpkg_list`, `apt_simulate` | Works from local dpkg DB; `apt update` may fail offline — tool must report that cleanly, not hang on WAN |
| **Process / resources** | `ps_top`, `disk_df`, `memory_free`, `loadavg` | Read-only local |
| **Network** | `ip_addr`, `ss_listen`, `ping` (optional), local DNS config read, `nft`/`ufw` status | Diagnose **local** stack; do not require external DNS/HTTP success for the tool to be “working” |
| **Users / auth** | `who`, `last_logins`, `failed_ssh` | Local auth logs |
| **Hardware** | `lsblk`, `smart_status` | Local only |

Implementation sketch:

```
mcp/linux_admin/
  pyproject.toml
  uv.lock                 # committed
  src/linux_admin_mcp/
    server.py
    tools/
      systemd.py
      journal.py
      packages.py
      network.py
      resources.py
    policy.py
    exec.py
vendor/                   # or node_modules committed via bootstrap path
  mcp/
    filesystem/
    ...
```

**Execution policy (hard rules in `exec.py`):**

- No shell interpolation; argv arrays only.
- Binary allowlist (`systemctl`, `journalctl`, `apt-get`, `dpkg`, `ip`, `ss`, `df`, …).
- Timeouts and output caps (spill large output to local files).
- Mutations require `confirm=true` **and** Grok permission approval.
- Elevated tools call the shared **sudo runner** (§6.2); they never embed passwords in argv visible to the model.
- **No raw `run_shell` tool in v1.**
- **Core tool surface** has no required outbound internet. Optional online tools (if any) live behind explicit names (`web_search`, `fetch_url`, …), document offline unavailability, and never block other tools.
- Package tools: prefer `dpkg-query`, `apt-cache` (local), `apt-get -s` simulate; document that applying upgrades needs reachable mirrors *as an OS fact*. Diagnosis and planning from local state must still work offline.
- Credential tools (store/list/delete metadata, unlock session) live in `linux-admin-mcp` under a `credentials` group; **secret values are never returned in tool results**.

### 4.3 Tier C — Optional (Phase 3)

| Server | When | Offline rule |
|--------|------|--------------|
| Docker MCP | Docker present | Unix socket only; skills must not require `docker pull` |
| Local Prometheus / node_exporter | If already on host | `127.0.0.1` scrape only |
| Web search / fetch / remote docs MCP | Operator opt-in | Optional online layer; fail soft; off by default in offline profile |
| Playwright / cloud GitHub MCP | Operator opt-in only | Must not be required for core admin; avoid blocking startup |

### 4.4 Example project config (illustrative, offline-safe)

```toml
[models]
default = "ollama-admin"
# Do NOT set fork_secondary_model to a cloud model in this project.

[model.ollama-admin]
model = "qwen2.5-coder:14b"
base_url = "http://127.0.0.1:11434/v1"
name = "Ollama Admin"
api_backend = "chat_completions"
context_window = 32768
temperature = 0.2
max_completion_tokens = 8192

[model.ollama-fast]
model = "llama3.1:8b"
base_url = "http://127.0.0.1:11434/v1"
name = "Ollama Fast"
api_backend = "chat_completions"
context_window = 16384
temperature = 0.3

# Vendored entrypoint — no npx -y, no registry
[mcp_servers.filesystem]
command = "/home/krich/src/linux-admin/vendor/mcp/filesystem/run.sh"
args = [
  "/home/krich/src/linux-admin",
  "/tmp/linux-admin-staging",
]
enabled = true
startup_timeout_sec = 30

[mcp_servers.linux-admin]
command = "/home/krich/src/linux-admin/mcp/linux_admin/.venv/bin/linux-admin-mcp"
args = []
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
tool_timeouts = { apt_simulate = 300, service_restart = 60 }

[mcp]
max_output_bytes = 40000
```

`scripts/bootstrap.sh` creates `vendor/` and `.venv`; `run.sh` wrappers use only local `node` + local `node_modules`.

---

## 5. Agent behavior (rules & skills)

### 5.1 Project rules — `AGENTS.md`

1. **Local-first.** Complete admin work using host state, in-repo skills, and core MCP. Optional online tools (search, fetch, etc.) only as enrichment when available — never as a hard dependency for local tasks.
2. **If online tools fail or WAN is down:** continue with the local path; report what could not be enriched. Do not stall the session.
3. **Read before write.** Inspect status/logs/config before changing anything.
4. **Plan for reversibility.** Prefer drop-ins, package holds, backups under staging.
5. **Stage then apply.** Propose diffs in-repo or `/tmp/linux-admin-staging`, then apply with approval.
6. **Prefer MCP admin tools** over ad-hoc shell when a specialized tool exists.
7. **Never** pipe remote content to a shell, disable security frameworks casually, or store secrets in the git repo or in chat/logs.
8. **Never request or echo sudo passwords in the model transcript.** Elevation goes through the credential store + sudo runner only.
9. **Report impact:** change, rollback, verify; note which sudo mode was used (`nopasswd` / `askpass` / `cached` / `tty` / `manual`) without secrets.
10. **Local model awareness:** short tool results; summarize large logs.
11. **Knowledge source order:** host state → in-repo skills/docs → local man pages → **optional** online search/docs if configured and reachable.

### 5.2 Skills (repo-local only)

| Skill | Trigger | Behavior |
|-------|---------|----------|
| `diagnose-service` | service down/failing | status → journal → deps → config → fix plan |
| `package-update` | updates / upgrade | local upgradable list → simulate → apply if approved **and** mirrors available |
| `disk-pressure` | disk full | df/du → cleanup plan from local state |
| `network-diagnose` | local connectivity | addr, routes, ss, resolver config, firewall — works offline for local stack |
| `boot-health` | post-reboot failures | failed units, journal `-b -p err` |
| `harden-check` | security check | listening ports, failed SSH, local hardening state |

No skill may list “search the web” or “fetch CVE page” as a **required** step. Optional “if network available…” enrichment is fine.

### 5.3 Permission posture

| Mode | Use |
|------|-----|
| Default interactive | Approve mutations |
| `always-approve` | **Forbidden** for production admin on this host |
| Headless / cron | Read-only MCP subset only |

Override any user-global `always-approve` for this project’s sessions.

---

## 6. Safe change workflow, credentials, and sudo

```
1. Observe   → local MCP read tools
2. Hypothesize → agent explains root cause (local knowledge)
3. Propose   → staging / git
4. Review    → human diff + rollback
5. Apply     → gated MCP + adaptive sudo runner (§6.2)
6. Verify    → local status/logs/smoke
7. Record    → local memory store + optional local git commit
   (audit log records elevation mode, never passwords)
```

### 6.1 Per-host credential repository

Each machine has its own credential repository. The agent must work correctly when cloned to many hosts without sharing secrets.

#### Identity

| Field | Source | Purpose |
|-------|--------|---------|
| `host_id` | `/etc/machine-id` (preferred) or stable hostname+product UUID | Partition secrets so a copied home dir does not reuse the wrong host’s material without explicit rebind |
| `hostname` | `hostname -f` / `hostname` | Human-readable label in listings |
| `username` | `$USER` / configured admin principal | Which account’s sudo password or key material |

#### Storage location (local only — never in git)

Recommended layout (XDG):

```
$XDG_DATA_HOME/linux-admin/          # default: ~/.local/share/linux-admin/
  hosts/
    <host_id>/
      meta.json                      # non-secret: hostname, sudo_mode hint, timestamps
      # secrets NOT in plain JSON when keyring available:
  # OS keyring entries (preferred for secret material):
  #   service: linux-admin
  #   account: sudo:<host_id>:<username>
  #   account: generic:<host_id>:<name>
```

Fallback when no keyring daemon is available (headless / minimal systems):

```
$XDG_DATA_HOME/linux-admin/hosts/<host_id>/secrets.age   # or .enc
# encrypted at rest with a host unlock secret
# unlock via: interactive passphrase once per session, or file mode 0600
# only if user explicitly chose "file backend" at bootstrap
```

| Backend | When | Notes |
|---------|------|-------|
| **A. OS keyring** (libsecret / kwallet / Secret Service) | Desktop / user session with agent | Preferred; secrets never in world-readable files |
| **B. Encrypted file store** | Headless servers, no keyring | age or similar; passphrase unlocked into an in-memory session cache |
| **C. Metadata-only** | Host is NOPASSWD / polkit only | No password stored; `meta.json` records `sudo_mode: nopasswd` |

**Hard rules**

1. Credential store paths are **gitignored** and live outside the repo tree by default (`XDG_DATA_HOME`, not `./.linux-admin` in the project unless the operator opts in for a portable USB-style layout).
2. **Never** commit `meta.json` with secrets, `.env` with passwords, or key material.
3. Tool results and audit logs may include: host_id, username, credential *names*, backend type, last-used time, sudo mode. They must **never** include secret values, askpass output, or environment dumps that contain passwords.
4. The LLM must not be given tools like `credentials_get_secret`. Only `credentials_status`, `credentials_set` (write-only path via local CLI), `credentials_delete`, `credentials_list` (names only).
5. Offline: all backends are local; no vault cloud, no network secret managers in v1.

#### Record types (v1)

| Kind | Purpose | Secret? |
|------|---------|---------|
| `sudo_password` | Feed `SUDO_ASKPASS` when host requires a password | Yes (keyring / encrypted) |
| `sudo_policy` | Hint: `auto` \| `nopasswd` \| `password` \| `tty` \| `manual` | No |
| `sudoers_profile` | Optional label linking to `scripts/sudoers.example` variant | No |
| `generic` (optional later) | Named local secrets for future host-local tools | Yes |
| `ssh_key_path` (optional later) | Path to local key file for *this* host’s admin scripts | Path only; key stays on disk |

v1 focus: **sudo + policy metadata**. Generic secrets are schema-ready but not required for MVP elevation.

#### Operator UX

```bash
# CLI helpers (implemented in Phase 2/3)
linux-admin creds init              # bind this machine-id, choose backend
linux-admin creds set-sudo          # prompt on TTY; store in keyring/file; never argv
linux-admin creds status            # mode, backend, whether password present (bool)
linux-admin creds clear-sudo        # delete sudo secret for this host
linux-admin creds doctor            # can we elevate? which mode?
```

`set-sudo` reads the password only from a **TTY or secure prompt** (or stdin when explicitly piped by the operator). It never accepts the password as a CLI flag (avoids shell history).

#### Multi-host mental model

- Laptop A and server B each run the agent with **their own** store under that host’s `host_id`.
- Copying the git repo does **not** copy credentials.
- Optional later: export/import of *encrypted* blobs for disaster recovery — not required for v1; if added, still offline and operator-driven.

---

### 6.2 Adaptive sudo runner (flexible elevation)

Hosts differ. The runner **probes and adapts** instead of assuming one policy.

#### Modes

| Mode | Detection / selection | Behavior |
|------|----------------------|----------|
| **`cached`** | `sudo -n true` succeeds because timestamp is still valid | Run `sudo -n -- <cmd>` without touching the credential store |
| **`nopasswd`** | `sudo -n true` succeeds even with empty timestamp (or policy hint + probe) | Same as cached; record hint `nopasswd` in meta for faster future path |
| **`askpass`** | `sudo -n` fails; store has `sudo_password` for this host/user; non-interactive session OK | Set `SUDO_ASKPASS` to a **short-lived helper** that prints the password to stdout once; run `sudo -A -n -- <cmd>` (or `-A` without `-n` per sudo version); helper zeros memory after use |
| **`tty`** | `sudo -n` fails; no stored password (or askpass disabled); controlling TTY available | Run `sudo -- <cmd>` attached to the operator TTY so the human types the password (agent does not see it) |
| **`manual`** | No TTY, no stored password, `sudo -n` fails | Do **not** block forever. Return structured error: exact command for the operator to run; optional “retry after you `sudo -v`” |
| **`denied`** | sudo returns auth failure / not in sudoers | Surface error; do not spin or spray password attempts |

**Policy resolution order (default `sudo_policy: auto`):**

```
1. If command is not in elevate-allowlist → refuse (even if sudo would work)
2. Probe: sudo -n true
   ├─ success → mode=cached|nopasswd; run with sudo -n
   └─ fail →
        3. If meta.sudo_policy == manual → manual
        4. If password in store and askpass enabled → askpass
        5. Else if stdin is a TTY (or configured PTY) → tty
        6. Else → manual (structured handoff)
```

Operators may **pin** a mode in `meta.json` / `sudo_policy` when auto-detection is wrong (e.g. force `manual` on a hardened host, force `askpass` for headless automation with a stored secret).

#### Allowlist and argv shape

```text
sudo -n -- /usr/bin/systemctl restart nginx.service
#          ^ absolute path preferred; no shell; no password on argv
```

- Always prefer `sudo --` + absolute binary path from the same allowlist as non-elevated exec.
- Prefer `sudo -n` whenever possible so a hung password prompt cannot deadlock headless agents.
- For askpass: only `sudo -A` (or equivalent); password goes through the askpass program, not `echo password | sudo -S` **unless** askpass is unavailable — and if `-S` is used as a last resort, stdin must be a pipe from the credential module, never logged, and never exposed to the LLM.

#### Askpass helper design

```
linux-admin-askpass   # tiny binary/script
  - reads secret from keyring/session cache (not from env var content in /proc if avoidable)
  - prints password + newline to stdout once
  - exits
  - invoked only by sudo via SUDO_ASKPASS
  - must not be a general “print any secret” tool callable by the model with arbitrary ids
```

Optional: session unlock — operator runs `linux-admin creds unlock` once; password sits in a **user-private memory or mode-0600 session socket** for N minutes, then expires. Reduces keyring prompts without leaving secrets in the model context.

#### Interaction with Grok permissions

Elevation is a **second gate** after tool approval:

1. Human approves the mutating tool call in Grok (or policy allows read-only elevated probes if explicitly configured).
2. Sudo runner selects mode and elevates.
3. Audit line: `{tool, argv, sudo_mode, host_id, success, duration}` — no secrets.

If mode is `manual`, the tool result tells the agent/operator what to run; the agent should **stop and wait** rather than invent alternate privilege escalation.

#### What we deliberately support

| Scenario | Supported? | How |
|----------|------------|-----|
| Desktop laptop, password sudo, interactive Grok | Yes | `tty` or `askpass` after `creds set-sudo` |
| Server, NOPASSWD for allowlisted systemctl/apt | Yes | `nopasswd` / `cached` |
| Server, password required, no TTY (headless agent) | Yes | stored password + `askpass`, or `manual` |
| Valid sudo ticket from recent human `sudo -v` | Yes | `cached` via `sudo -n` |
| Operator refuses to store passwords | Yes | `tty` or `manual` only; meta `sudo_policy: tty\|manual` |
| Fully root-run agent | No (default) | Rejected; document break-glass only outside project defaults |

#### Optional sudoers profiles (complementary, not exclusive)

Storing a password is **not required** when NOPASSWD allowlists are acceptable:

```
# scripts/sudoers.example — install by hand after review
# %linux-admin ALL=(root) NOPASSWD: /usr/bin/systemctl, /usr/bin/journalctl, ...
```

Hosts can mix: broad password sudo for rare actions, NOPASSWD for a small allowlist. The runner still probes with `sudo -n` first.

---

### 6.3 Implementation sketch (MCP + library)

```
mcp/linux_admin/src/linux_admin_mcp/
  creds/
    store.py          # backend interface: keyring | file | metadata-only
    host_id.py        # machine-id binding
    cli.py            # linux-admin creds …
  elevate/
    probe.py          # sudo -n true, detect mode
    runner.py         # run allowlisted argv under chosen mode
    askpass.py        # helper entrypoint
  tools/
    credentials.py    # list/status/delete metadata tools (no secret readback)
    systemd.py        # uses elevate.runner when needed
```

Document full threat model and backend choice in `docs/security.md` and operator steps in `docs/credentials.md`.

---

## 7. Repository layout (target)

```
linux-admin/
├── README.md
├── PLAN.md
├── AGENTS.md
├── LICENSE
├── .gitignore
├── .grok/
│   └── config.toml           # Ollama-only models + vendored MCP paths
├── skills/                   # offline runbooks
├── mcp/linux_admin/          # custom MCP + uv.lock + .venv (local)
├── vendor/                   # bootstrap-produced JS MCP trees (gitignored or LFS policy TBD)
│   └── mcp/...
├── scripts/
│   ├── bootstrap.sh          # ONLINE: install deps, pull models, vendor MCP
│   ├── doctor.sh             # basic health
│   ├── doctor-offline.sh     # assert CORE path only (optional online may be red)
│   ├── linux-admin-askpass   # SUDO_ASKPASS helper (no secret in repo)
│   └── sudoers.example       # optional NOPASSWD profiles
├── docs/
│   ├── architecture.md
│   ├── offline.md
│   ├── credentials.md        # per-host store, backends, operator UX
│   ├── mcp-servers.md
│   ├── ollama-models.md
│   └── security.md           # threat model, sudo, audit
└── tests/
    ├── mcp/
    ├── elevate/              # mode matrix: nopasswd, askpass mock, manual
    └── offline/
```

**Not in git (runtime, per host):** `$XDG_DATA_HOME/linux-admin/hosts/<host_id>/` and OS keyring items.

`vendor/` may be gitignored if bootstrap is mandatory on each machine; then lockfiles **must** be committed and bootstrap must be deterministic. Prefer documenting both: “bootstrap once online, then airplane mode forever.”

---

## 8. Phased delivery

### Phase 0 — Repo & docs

- [x] `PLAN.md`, `README.md`, `.gitignore`
- [x] GitHub repo `krich11/linux-admin`
- [x] Offline constraint documented (core path + optional online layer)
- [x] Per-host credentials + adaptive sudo design (§6)
- [ ] `docs/offline.md` / `docs/credentials.md` full operator docs in follow-up PRs

### Phase 1 — Local LLM + offline baseline MCP (1–2 days)

1. Install Ollama; pull models; **prove inference with WAN disabled**.
2. Project `.grok/config.toml`: default = Ollama admin model; core path does not require cloud models.
3. Vendor filesystem (and optional memory/git) MCP; wire absolute local commands.
4. `scripts/bootstrap.sh` + `scripts/doctor.sh` + `scripts/doctor-offline.sh`.
5. Smoke test full prompt loop offline.
6. Verify Grok does not require live cloud model access for this project session.

**Exit criteria:** Airplane-mode (or default route down) session can read allowlisted files and answer admin questions via Ollama; doctor-offline green.

### Phase 2 — Custom `linux-admin-mcp` + credential store + sudo runner (4–6 days)

1. Read-only tools (systemd, journal, df, ss).
2. **Credential repository:** host_id binding, keyring + encrypted-file backends, `linux-admin creds` CLI.
3. **Adaptive sudo runner:** probe order, modes `cached` / `nopasswd` / `askpass` / `tty` / `manual`, askpass helper.
4. Mutation tools call elevate.runner; policy + confirm gates; core tools remain offline-capable.
5. Skills: diagnose-service, boot-health, network-diagnose (local).
6. Unit tests: allowlist, offline apt behavior, **elevation mode matrix** (mock sudo), assert secrets never appear in tool JSON.

**Exit criteria:** Offline diagnosis; restart works on both a NOPASSWD-style path and a password path (askpass or tty); `creds status` / `creds doctor` accurate; no password in logs.

### Phase 3 — Packages, hardening, polish (2–4 days)

1. Apt/dpkg tools with clear offline semantics (elevated as needed).
2. package-update / disk-pressure skills.
3. Optional local Docker socket MCP (no pull required for core use).
4. Headless read-only health report (cron-friendly; core path offline).
5. Session unlock TTL for stored sudo secret; audit fields for sudo_mode.
6. Optional online enrichment MCP (search/fetch) with fail-soft behavior and offline profile toggle.

**Exit criteria:** Health report and dry-run package plan from local state without internet; headless elevate via askpass when configured, or clean `manual` handoff when not; online helpers soft-fail without breaking core session.

### Phase 4 — Hardening & ops (ongoing)

- Audit log `logs/agent-audit.jsonl` (local).
- Expand allowlists carefully; never add raw shell as a core tool.
- Stronger local models as hardware allows.
- Keep default project profile on Ollama; optional cloud models elsewhere must not become required for this repo’s core path.
- Revisit optional online helpers for quality; never promote them into doctor-offline requirements.

---

## 9. Testing strategy

| Level | What |
|-------|------|
| Doctor | Ollama up, models on disk, MCP entrypoints exist and start |
| Doctor-offline | Drop default route; core smoke prompt must pass; optional online tools may fail/absent |
| MCP unit | Allowlist rejects `bash -c`, `curl`, `docker pull`; caps output |
| Elevate unit | Mode matrix with fake `sudo`; askpass never logs secret; `manual` returns structured error |
| Creds unit | host_id isolation; list/status never returns secret bytes; file backend 0600 |
| Integration | Diagnose failed unit; elevate restart on password and NOPASSWD fixtures |
| Regression | Golden tool-call transcripts (redact any credential fields) |
| Safety | Writes outside allowlist fail; no network tools; no secret in audit JSON |

**Offline test recipe (document in `docs/offline.md`):**

```bash
# Example — adjust for environment; do not run blindly on remote-only hosts
sudo ip route del default   # or: unplug NIC / nmcli networking off
./scripts/doctor-offline.sh
grok -m ollama-admin -p "List failed systemd units and free disk space"
# restore default route afterward
```

---

## 10. Risks & mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Grok CLI requires cloud auth to start | Blocks offline use | Phase 1 spike; local-only config; alternate harness only if proven necessary |
| Local model weak at tool calling | Bad admin actions | Coder-tuned models; short schemas; golden tests |
| Unbounded journal reads | Context blowup | Caps, since filters |
| Privilege escalation | Host compromise | No raw shell; sudo allowlist; human tool approval; least-privilege sudoers optional |
| Credential theft from disk | Password leak | Keyring preferred; encrypted file; 0600; never git; never model context |
| Password in LLM logs | Secret exfil via sessions | No secret tool readback; redact audit; askpass isolated |
| Wrong sudo mode (hang on password) | Stuck headless agent | Prefer `sudo -n`; fail to `manual` instead of indefinite prompt |
| Host A creds used on host B | Cross-machine misuse | Bind store to `machine-id`; refuse mismatch without re-init |
| `/etc` corruption | Outage | Staging, diffs, drop-ins |
| Ollama down | Core path unusable | Doctor; fix local Ollama (cloud is not the required backup for this project) |
| `npx -y` / uvx at runtime | Offline failure + supply chain | Vendor + lockfiles; offline doctor asserts no registry access |
| Apt mirrors unreachable | Cannot install new packages | Expected; agent still diagnoses; report “needs mirror/cache” |
| Optional online MCP blocks startup | Offline session unusable | Core MCP only for start; online MCP lazy/timeout; offline profile disables them |
| Agent refuses work without search | False offline failure | Skills local-first; online is enrichment only |

---

## 11. Open decisions (Phase 1–2)

1. **Default Ollama model** after benchmarking on `phoenix`.
2. **Default credential backend:** keyring-first with file fallback, or file-only on servers? (Recommend keyring-first, auto-fallback.)
3. **Default `sudo_policy`:** `auto` (recommend) vs require explicit pin per host.
4. **Whether headless sessions may use stored sudo passwords** by default, or require an explicit `creds allow-askpass` flag (recommend explicit opt-in for askpass automation).
5. **`/etc` writes** via filesystem MCP vs apply-only tools.
6. **Vendor strategy:** commit `vendor/` vs bootstrap-only with lockfiles.
7. **Python vs Node** for `linux-admin-mcp` (recommend **Python + uv**).
8. **Grok offline auth:** confirm whether a live xAI session is required when using only custom Ollama models; document result in `docs/offline.md`.

---

## 12. Success metrics

- `doctor-offline.sh` green with no default route.
- Full tool-using admin session with WAN down (diagnose + stage + verified read-only report).
- Zero **required** core MCP tools that need non-loopback network I/O; optional online tools are documented and fail soft.
- Zero unapproved host mutations in interactive mode.
- P95 Ollama tool-loop latency acceptable interactively (target &lt; 15s/step on chosen model).
- All custom MCP tools covered by allowlist unit tests including “no WAN binaries.”
- Elevation succeeds on at least two fixtures: **NOPASSWD** and **password** (askpass or tty).
- Credential status/list APIs never return secret material in automated tests.

---

## 13. Immediate next actions

1. Install Ollama; pull models; **airplane-mode inference test**.
2. Scaffold `.grok/config.toml` (Ollama-only), `AGENTS.md`, bootstrap + doctor + doctor-offline.
3. Vendor filesystem MCP; smoke test offline.
4. Scaffold `linux-admin-mcp` with `service_status` vertical slice.
5. Spike: Grok + Ollama with network disabled; record any cloud dependency.
6. Design spike: `creds` CLI + sudo probe on this host (password vs `-n`); document observed mode in `docs/credentials.md`.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Core runtime network | **None required** | Full local admin capacity offline |
| Optional online services | Allowed, fail soft | Search/CVE/fetch etc. must not block core path |
| Inference (default) | **Ollama** (loopback) | Required for core path; cloud not required |
| Cloud as hard dependency | **No** | Fail closed on local stack for core work |
| Agent host | Grok CLI if offline-viable | Validate in Phase 1 |
| Tool boundary | Vendored local MCP + custom server | No registry required at session start for core |
| Fetch / web MCP | Optional enrichment | Not required; soft-fail offline |
| Knowledge | Local-first, online optional | Skills never require the web |
| Mutations | Double-gated | High blast radius |
| Raw shell MCP | Not in v1 | Injection / safety |
| Credentials | Per-host store under XDG / keyring | Offline; not in git; bound to machine-id |
| Sudo | Adaptive multi-mode runner | Password, NOPASSWD, cache, TTY, manual handoff |
| Secrets to LLM | Never | Status/metadata only; askpass outside model |

---

## PR Plan

| PR | Title | Scope | Depends on |
|----|-------|-------|------------|
| **PR0** | docs: plan + offline + credentials/sudo design | `PLAN.md`, `README.md`, `.gitignore` | — |
| **PR1** | feat: Ollama-only Grok config + offline doctor | `.grok/config.toml`, `docs/offline.md`, `docs/ollama-models.md`, `scripts/doctor*.sh` | PR0, Ollama + models on disk |
| **PR2** | feat: vendored baseline MCP (no npx -y) | `vendor/` or bootstrap, `AGENTS.md`, `scripts/bootstrap.sh` | PR1 |
| **PR3** | feat: linux-admin-mcp read-only slice | `mcp/linux_admin/**`, tests | PR2 |
| **PR4** | feat: per-host credential repository | `creds/*`, CLI, keyring/file backends, `docs/credentials.md` | PR3 |
| **PR5** | feat: adaptive sudo runner + askpass + mutation tools | `elevate/*`, sudoers.example, skills, `docs/security.md` | PR4 |
| **PR6** | feat: package/disk skills + offline apt semantics | skills, package tools | PR5 |
| **PR7** | feat: headless read-only health report | scripts, docs | PR5 |

Each PR must preserve the **core offline contract** (doctor-offline green), the credential contract (no secrets in git or tool results), and the rule that optional online features never become hard dependencies.
