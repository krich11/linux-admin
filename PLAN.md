# Linux Admin Agent — Implementation Plan

**Status:** Planning  
**Owner:** krich11  
**Host:** Ubuntu 24.04 LTS (`phoenix`)  
**Agent harness:** Grok CLI / ACP (local)  
**LLM backend:** Ollama (OpenAI-compatible API on `http://localhost:11434/v1`)  
**Repo:** `krich11/linux-admin`

---

## 1. Goals

Build a **local-first Linux administration agent** that:

1. Runs entirely on the host (no required cloud LLM dependency for day-to-day admin work).
2. Uses **Ollama** for inference via Grok’s custom-model configuration.
3. Exposes safe, scoped **local MCP servers** for filesystem, process/service control, packages, logs, network diagnostics, containers, and git.
4. Encodes admin workflow knowledge as **project rules + skills** so the agent prefers inspect → plan → apply → verify over blind shell.
5. Defaults to **least privilege** and explicit confirmation for destructive actions.

### Non-goals (v1)

- Multi-host orchestration / fleet management (Ansible replacement).
- Unattended root automation across the network.
- Replacing cloud models for coding-heavy tasks (Ollama is for local admin; hybrid is allowed later).
- Building a full custom agent runtime from scratch (reuse Grok as the tool-using agent host).

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Operator (TUI / headless / ACP IDE)                             │
└────────────────────────────┬─────────────────────────────────────┘
                             │ prompts / approvals
┌────────────────────────────▼─────────────────────────────────────┐
│  Grok agent (this repo as cwd)                                   │
│  • AGENTS.md / .grok project config                              │
│  • Skills (diagnose, package, service, log, network)             │
│  • Permission policy (read-heavy; write gated)                   │
└───────┬───────────────────────────────┬──────────────────────────┘
        │ inference                     │ tools
        ▼                               ▼
┌───────────────────┐     ┌────────────────────────────────────────┐
│ Ollama            │     │ Local MCP servers (stdio)              │
│ :11434/v1         │     │  filesystem | shell-safe | systemd     │
│ models:           │     │  journal   | packages  | network       │
│  qwen2.5-coder    │     │  docker*   | git       | memory        │
│  llama3.1 / etc.  │     │  (*optional if Docker present)         │
└───────────────────┘     └────────────────────────────────────────┘
                             │
                             ▼
                      Host OS (Ubuntu 24.04)
                      systemctl, apt, journalctl, ip, ss, …
```

### Why Grok + Ollama + MCP

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Agent host | Grok CLI | Already installed; has MCP, permissions, sessions, ACP, project config |
| Models | Ollama OpenAI-compat API | Local, free at inference time, Grok-native custom model support |
| Tools | Local MCP servers | Portable tool boundary; can grow custom servers without forking Grok |
| Policy | Project rules + permission modes | Admin mistakes are high blast-radius; defaults must be conservative |

---

## 3. Prerequisites

### 3.1 Host tools (already largely present)

- Ubuntu 24.04, `systemctl`, `journalctl`, `python3`, Node 22 / `npx` (via nvm)
- `gh` authenticated as `krich11`
- Grok CLI with user config at `~/.grok/config.toml`

### 3.2 Ollama (required — currently not listening on this host)

At plan time, nothing answered on `127.0.0.1:11434`. Install and enable before Phase 1 validation:

```bash
# Official install (or distro package if preferred)
curl -fsSL https://ollama.com/install.sh | sh

# Service (system or user — prefer system if multi-user, user if laptop-only)
sudo systemctl enable --now ollama
# OR: systemctl --user enable --now ollama   # if installed that way

# Pull admin-capable models (adjust to GPU/RAM)
ollama pull qwen2.5-coder:14b      # strong tool-use / coding
ollama pull llama3.1:8b            # lighter general
# Optional larger: qwen2.5:32b, mistral-small, deepseek-r1 distill, etc.

ollama list
curl -s http://127.0.0.1:11434/api/tags | head
```

**Hardware note:** Pick default model size from available VRAM/RAM. Document the chosen default in `.grok/config.toml` after measuring latency on this machine.

### 3.3 Optional tools

| Tool | Use | MCP / skill impact |
|------|-----|--------------------|
| Docker / Podman | Container admin | Enable `docker` MCP only if present |
| `uv` / `uvx` | Fast Python MCP servers | Preferred launcher for Python MCPs |
| `smartmontools`, `lm-sensors` | Hardware health skills | Phase 3 |
| `fail2ban`, `ufw` | Security skills | Phase 3 |

---

## 4. Local MCP server inventory

Prefer **project-scoped** config in `.grok/config.toml` so the agent only gains these tools when working in this repo (or when explicitly loaded). Do not put secrets in committed files; use `${ENV_VAR}` references.

### 4.1 Tier A — MVP (Phase 1)

| Server name | Package / source | Purpose | Scope / safety |
|-------------|------------------|---------|----------------|
| `filesystem` | `@modelcontextprotocol/server-filesystem` | Read/write config trees, scripts, unit files under allowlisted roots | Allowlist only: e.g. `/etc` (read), `/var/log` (read), `~/src`, project dir; never `$HOME` wholesale with write |
| `git` | `@modelcontextprotocol/server-git` (or community equivalent) | Inspect/commit admin scripts and this repo | Repo root only |
| `memory` | `@modelcontextprotocol/server-memory` | Persist host facts (hostname roles, known services, last incident notes) | Local JSON store under `.linux-admin/memory/` |
| `fetch` | `@modelcontextprotocol/server-fetch` | Pull docs / CVE pages when offline knowledge is insufficient | Outbound HTTP; optional kill-switch |

**Filesystem allowlist (recommended MVP):**

```
read:  /etc, /var/log, /usr/lib/systemd, /lib/systemd, /proc, /sys (limited), project root
write: project root, /tmp/linux-admin-staging, optional ~/admin-work
```

Destructive host edits (`/etc` write) should go through a **staged patch workflow** (see §6), not direct MCP write in v1.

### 4.2 Tier B — Admin-specific (Phase 2, custom MCP)

Build a thin **`linux-admin-mcp`** Python (or Node) stdio server in this repo:

| Tool groups | Example tools | Notes |
|-------------|---------------|-------|
| **Systemd** | `service_status`, `service_logs`, `service_restart`, `list_failed_units` | Restart/stop require elevated policy flag |
| **Journal** | `journal_query`, `journal_since`, `boot_errors` | Wrap `journalctl -o json` with size caps |
| **Packages** | `apt_list_upgradable`, `apt_changelog`, `apt_install_plan` | Prefer dry-run / simulate; apply is separate gated tool |
| **Process / resources** | `ps_top`, `disk_df`, `memory_free`, `loadavg` | Read-only |
| **Network** | `ip_addr`, `ss_listen`, `ping`, `dns_lookup`, `nft_or_ufw_status` | No arbitrary `curl \| sh` |
| **Users / auth** | `who`, `last_logins`, `failed_ssh` | Read-only first |
| **Hardware** | `lsblk`, `smart_status` (optional) | Phase 3 |

Implementation sketch:

```
mcp/linux_admin/
  pyproject.toml
  src/linux_admin_mcp/
    server.py          # MCP stdio entry
    tools/
      systemd.py
      journal.py
      packages.py
      network.py
      resources.py
    policy.py          # allow/deny, require_confirm, sudo strategy
    exec.py            # bounded subprocess runner (timeout, max bytes)
```

**Execution policy (hard rules in `exec.py`):**

- Default: no shell interpolation; argv arrays only.
- Allowlist of binaries (`systemctl`, `journalctl`, `apt-get`, `dpkg`, `ip`, `ss`, `ping`, `df`, …).
- Timeouts (e.g. 30s default, 300s for apt) and output cap (e.g. 200 KiB) with spill to file.
- Mutations require `confirm=true` tool arg **and** Grok permission approval (double gate).
- Never expose a raw `run_shell` tool in v1.

### 4.3 Tier C — Optional integrations (Phase 3)

| Server | When to enable |
|--------|----------------|
| Docker MCP | If Docker/Podman is installed and used on host |
| Playwright (existing user MCP) | Browser-based admin UIs only; keep out of default admin profile |
| GitHub MCP | Only when managing this repo / infra-as-code remotes — already available globally if needed |
| Prometheus / node_exporter HTTP | If metrics stack exists locally |

### 4.4 Example project MCP config (illustrative)

`.grok/config.toml` (committed skeleton; paths adjusted per machine):

```toml
[models]
default = "ollama-admin"

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

[mcp_servers.filesystem]
command = "npx"
args = [
  "-y",
  "@modelcontextprotocol/server-filesystem",
  "--",
  # tighten after install; example roots:
  "/home/krich/src/linux-admin",
  "/tmp/linux-admin-staging",
]
enabled = true
startup_timeout_sec = 60

[mcp_servers.linux-admin]
command = "uv"
args = ["run", "--directory", "mcp/linux_admin", "linux-admin-mcp"]
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
tool_timeouts = { apt_install_plan = 300, service_restart = 60 }

[mcp]
max_output_bytes = 40000
```

Use absolute `npx` path if needed (as in the existing Playwright config under `~/.grok/config.toml`).

---

## 5. Agent behavior (rules & skills)

### 5.1 Project rules — `AGENTS.md`

Mandatory operating principles:

1. **Read before write.** Inspect status/logs/config before changing anything.
2. **Plan for reversibility.** Prefer `systemctl edit` drop-ins, package holds, and backups of files under `/etc` before edits.
3. **Stage then apply.** Write proposed unit/config changes into the repo or `/tmp/linux-admin-staging`, show diff, then apply with explicit approval.
4. **Prefer MCP admin tools over ad-hoc shell** when a specialized tool exists (structured output, caps, allowlists).
5. **Never** run remote pipe-to-shell, disable security frameworks casually, or store secrets in the repo.
6. **Report impact:** what changed, how to rollback, how to verify.
7. **Local model awareness:** keep tool results short; summarize large logs; avoid dumping multi-MB journal output into context.

### 5.2 Skills (repo-local)

| Skill | Trigger | Behavior |
|-------|---------|----------|
| `diagnose-service` | “service X is down / failing” | status → recent journal → deps → config → suggest fix |
| `package-update` | “updates / upgrade” | list upgradable → changelogs → risk notes → simulate → apply if approved |
| `disk-pressure` | “disk full” | df/du hotspots → logrotate / orphan packages → safe cleanup plan |
| `network-diagnose` | “can’t reach / DNS / port” | addr, routes, ss, DNS, firewall status |
| `boot-health` | “failed after reboot” | failed units, journal `-b -p err`, last boot |
| `harden-check` | “security check” | listening ports, failed SSH, unattended-upgrades status (read-only) |

Each skill is a short `SKILL.md` with steps, allowed tools, and stop conditions.

### 5.3 Permission posture

| Mode | Use |
|------|-----|
| Default interactive | Approve mutations; auto-allow read-only tools if Grok supports granular modes |
| `always-approve` | **Forbidden** for production admin sessions on this host |
| Headless / cron | Separate profile with **read-only** MCP tool subset only |

Note: current user `~/.grok/config.toml` has `permission_mode = "always-approve"`. For this project, override in **project** config or session flags to require confirmation for mutating tools.

---

## 6. Safe change workflow

```
1. Observe   → MCP read tools (status, journal, files)
2. Hypothesize → agent explains root cause
3. Propose   → write patch/unit drop-in into staging or git branch
4. Review    → human sees diff + rollback steps
5. Apply     → gated MCP tool (sudo strategy below)
6. Verify    → re-check status/logs/smoke tests
7. Record    → memory MCP + optional git commit of the change notes
```

### Sudo strategy

Options (pick one in Phase 2; default recommendation = A):

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| **A. Polkit / sudoers allowlist** | Dedicated `linux-admin-agent` user or group with NOPASSWD for specific commands | Auditable, least privilege | Needs careful sudoers design |
| **B. Interactive sudo** | Agent prints commands; human runs with sudo | Safest | Less “agentic” |
| **C. Root agent** | Run entire agent as root | Simple | **Rejected** for default |

Document the chosen strategy in `docs/security.md` when implemented.

---

## 7. Repository layout (target)

```
linux-admin/
├── README.md                 # quickstart
├── PLAN.md                   # this document
├── AGENTS.md                 # project agent rules
├── LICENSE
├── .gitignore
├── .grok/
│   └── config.toml           # project models + MCP (no secrets)
├── skills/
│   ├── diagnose-service/SKILL.md
│   ├── package-update/SKILL.md
│   ├── disk-pressure/SKILL.md
│   ├── network-diagnose/SKILL.md
│   └── boot-health/SKILL.md
├── mcp/
│   └── linux_admin/          # custom MCP server package
│       ├── pyproject.toml
│       ├── README.md
│       └── src/linux_admin_mcp/...
├── scripts/
│   ├── bootstrap.sh          # install ollama checks, pull models, uv sync
│   ├── doctor.sh             # validate ollama + MCP connectivity
│   └── sudoers.example       # example least-privilege sudoers snippet
├── staging/                  # gitignored working patches (optional)
├── docs/
│   ├── architecture.md
│   ├── mcp-servers.md
│   ├── ollama-models.md
│   └── security.md
└── tests/
    └── mcp/                  # unit tests for allowlists & parsers
```

---

## 8. Phased delivery

### Phase 0 — Repo & docs (this PR / initial commit)

- [x] Create `PLAN.md`
- [ ] `README.md` quickstart outline
- [ ] GitHub repo `krich11/linux-admin`
- [ ] Initial commit + push

### Phase 1 — Local LLM + baseline MCP (1–2 days)

1. Install/enable Ollama; pull 1–2 models; measure tokens/s on this GPU/CPU.
2. Add `[model.ollama-*]` entries (project and/or user config).
3. Add project `.grok/config.toml` with `filesystem` (+ optional `memory`, `git`).
4. Write `AGENTS.md` and `scripts/doctor.sh` (curl Ollama, `grok mcp doctor`).
5. Smoke test: `grok -m ollama-admin -p "Summarize disk usage of /var"` with filesystem MCP.

**Exit criteria:** Agent answers admin questions using Ollama; can read allowlisted paths via MCP; doctor script green.

### Phase 2 — Custom `linux-admin-mcp` (3–5 days)

1. Scaffold Python MCP server with read-only tools (systemd status, journal, df, ss).
2. Add mutation tools behind `confirm` + policy module.
3. Wire sudoers example; document interactive fallback.
4. Skills: `diagnose-service`, `boot-health`, `network-diagnose`.
5. Unit tests for command allowlist and output truncation.

**Exit criteria:** End-to-end “nginx is failing” style diagnosis without free-form shell; restart only after approval.

### Phase 3 — Packages, hardening, polish (2–4 days)

1. Apt simulate / upgrade plan tools.
2. `package-update` and `disk-pressure` skills.
3. Optional Docker MCP.
4. Memory: host inventory snapshot skill.
5. Headless read-only profile for scheduled health reports.

**Exit criteria:** Safe upgrade dry-run workflow; weekly health report via headless Grok + Ollama.

### Phase 4 — Hardening & ops (ongoing)

- Audit logs of agent actions (append-only `logs/agent-audit.jsonl`).
- Expand allowlists carefully; never add raw shell.
- Evaluate stronger local models as hardware allows.
- Optional hybrid: use cloud Grok for complex reasoning, Ollama for routine local tasks (`fork_secondary_model` patterns).

---

## 9. Testing strategy

| Level | What |
|-------|------|
| Doctor script | Ollama up, models present, MCP processes start |
| MCP unit tests | Allowlist rejects `bash -c`, caps output, parses journal JSON |
| Integration (manual) | Scripted prompts: diagnose failed unit, list listeners, dry-run apt |
| Regression | Golden transcripts of tool call sequences for skills |
| Safety | Attempts to write outside allowlist / run forbidden binaries must fail |

---

## 10. Risks & mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Local model weak at tool calling | Wrong or missing tool use | Prefer instruction-tuned coder models; keep tool schemas short; golden tests |
| Unbounded journal/file reads | Context blowup / hang | Output caps, line limits, `since` filters |
| Privilege escalation via agent | Host compromise | No raw shell; sudoers allowlist; human approval; no always-approve |
| Accidental `/etc` corruption | Outage | Staging + diffs + backups; drop-ins over in-place edits |
| Ollama downtime | Agent unusable | Doctor script; document fallback to cloud model in user config |
| MCP supply-chain (`npx -y`) | Malicious package | Pin versions in config once stable; prefer `uv` lock for custom server |

---

## 11. Open decisions (resolve during Phase 1–2)

1. **Default Ollama model** after benchmarking on `phoenix`.
2. **Sudo strategy** A vs B (§6).
3. **Whether `/etc` write via filesystem MCP is ever allowed**, or only via custom apply tools.
4. **Public vs private GitHub repo** (default: public plan + code; keep host-specific paths out of commits).
5. **Python vs Node** for `linux-admin-mcp` (recommend **Python + uv** for easy `journalctl`/systemd scripting).

---

## 12. Success metrics

- Cold-start doctor script succeeds in &lt; 30s.
- Diagnose a deliberately failed systemd unit in one session without manual journal diving.
- Zero unapproved host mutations in interactive mode.
- P95 Ollama tool-loop latency acceptable for interactive use (target &lt; 15s per step on chosen model).
- All custom MCP tools covered by allowlist unit tests.

---

## 13. Immediate next actions

After this plan is committed:

1. Install and start Ollama; pull candidate models; record sizes/latency in `docs/ollama-models.md`.
2. Scaffold `.grok/config.toml`, `AGENTS.md`, `scripts/bootstrap.sh`, `scripts/doctor.sh`.
3. Add filesystem MCP with tight allowlist; smoke-test with Ollama model.
4. Scaffold `mcp/linux_admin` with one read-only tool (`service_status`) as vertical slice.
5. Iterate skills and mutation policy.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent host | Grok CLI (not a greenfield runtime) | MCP, permissions, sessions already exist locally |
| Inference | Ollama OpenAI-compatible API | Local-first; first-class Grok custom model support |
| Tool boundary | Local MCP servers + custom `linux-admin-mcp` | Safer than free-form shell; testable allowlists |
| Config scope | Project `.grok/config.toml` | Admin tools only when in this workspace |
| Mutations | Double-gated (tool confirm + human permission) | High blast radius of Linux admin |
| Raw shell MCP | Not in v1 | Prevents prompt-injection → `rm -rf` class failures |

---

## PR Plan

| PR | Title | Scope | Depends on |
|----|-------|-------|------------|
| **PR0** | docs: initial plan and repo bootstrap | `PLAN.md`, `README.md`, `.gitignore`, LICENSE | — |
| **PR1** | feat: Ollama models + project Grok config skeleton | `.grok/config.toml`, `docs/ollama-models.md`, `scripts/doctor.sh` | PR0, Ollama installed on host |
| **PR2** | feat: baseline filesystem/git/memory MCP wiring | `.grok/config.toml`, `AGENTS.md`, bootstrap script | PR1 |
| **PR3** | feat: linux-admin-mcp read-only vertical slice | `mcp/linux_admin/**`, tests, docs | PR2 |
| **PR4** | feat: mutation tools + sudoers example + skills | skills/, policy, `docs/security.md` | PR3 |
| **PR5** | feat: package/disk skills + optional docker | more skills, optional MCP | PR4 |
| **PR6** | feat: headless read-only health report profile | scripts, docs | PR4 |

Each PR should be independently reviewable; host-specific absolute paths may live in untracked overrides or documented placeholders.
