# Linux Admin Agent — Implementation Plan

**Status:** Planning  
**Owner:** krich11  
**Host:** Ubuntu 24.04 LTS (`phoenix`)  
**Agent harness:** Grok CLI / ACP (local process only)  
**LLM backend:** Ollama only (`http://127.0.0.1:11434/v1`)  
**Repo:** `krich11/linux-admin`  
**Hard constraint:** **100% offline-capable at runtime** (see §1.1)

---

## 1. Goals

Build a **fully local Linux administration agent** that:

1. **Operates at full capacity with no internet reachability.** Inference, tools, docs, skills, and MCP servers must not call the public network at runtime.
2. Uses **Ollama only** for LLM inference (no cloud model fallback in this project’s default profile).
3. Exposes safe, scoped **local MCP servers** for filesystem, process/service control, packages, logs, network diagnostics, containers, and git — all launched from **pre-installed, vendored, or lockfile-resolved** binaries on disk.
4. Encodes admin workflow knowledge as **project rules + skills** (shipped in-repo) so the agent prefers inspect → plan → apply → verify over blind shell.
5. Defaults to **least privilege** and explicit confirmation for destructive actions.

### 1.1 Offline-first constraint (non-negotiable)

| Allowed | Not allowed at runtime |
|---------|------------------------|
| Install software from the internet **during bootstrap / provisioning** (Ollama, models, apt packages, pip/uv deps, MCP packages) | Any **required** call to the public internet for the agent to function |
| Local loopback (`127.0.0.1`) to Ollama and local services | Cloud LLM APIs (xAI, OpenAI, Anthropic, etc.) as default or fallback |
| LAN admin of **this host** (loopback, local sockets, optional local Docker API) | `npx -y` / `uvx` cold installs that hit registries on every session start |
| Using OS tools that *may* fail offline when the **task itself** needs the net (e.g. `apt update` with remote mirrors) | Agent features that **depend** on net success (CVE fetch, web search, remote MCP, telemetry) |
| Shipping man pages, skill docs, and runbooks **in the repo** | “Look it up online” as a primary skill step |

**Definition of done for offline:** With the host’s default route removed or WAN unplugged, after bootstrap has already completed:

1. Ollama serves the configured model(s) from local disk.
2. Grok starts with **only** project Ollama model(s) and **only** local MCP servers.
3. Full diagnose / stage / apply / verify loops work for local admin tasks (services, journals, disks, local networking, local package cache operations).
4. `scripts/doctor.sh` and `scripts/doctor-offline.sh` both pass.

**Bootstrap vs runtime**

```
[Bootstrap — internet OK]          [Runtime — internet optional / absent]
 install Ollama, pull models   →   ollama serve (local weights)
 uv sync / npm ci into vendor  →   node/python entrypoints from vendor/
 apt install host packages     →   systemctl, journalctl, dpkg, …
 clone/pull this repo          →   AGENTS.md, skills/, docs/ on disk
```

### Non-goals (v1)

- Multi-host orchestration / fleet management (Ansible replacement).
- Unattended root automation across the network.
- Cloud or hybrid LLM routing (explicitly out of scope for this project profile).
- Building a full custom agent runtime from scratch (reuse Grok as the tool-using agent host **in offline mode**).
- Live web/CVE/documentation fetch as part of core workflows.
- Depending on GitHub, npm registry, PyPI, or model hubs after first setup.

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
│  • default model = ollama-* only (no cloud model id)             │
│  • AGENTS.md / .grok project config                              │
│  • Skills + in-repo runbooks (no web fetch)                      │
│  • Permission policy (read-heavy; write gated)                   │
│  • No user MCP servers that require WAN (exclude playwright CDN, │
│    remote HTTP MCP, GitHub-cloud, etc. from project profile)     │
└───────┬───────────────────────────────┬──────────────────────────┘
        │ loopback only                 │ stdio only (local procs)
        ▼                               ▼
┌───────────────────┐     ┌────────────────────────────────────────┐
│ Ollama            │     │ Local MCP servers (vendored entrypts)  │
│ 127.0.0.1:11434   │     │  filesystem | git | memory             │
│ weights on disk   │     │  linux-admin (systemd/journal/…)       │
│ no model pull at  │     │  docker* (local socket only)           │
│ runtime           │     │  *optional; no registry pulls          │
└───────────────────┘     └────────────────────────────────────────┘
                             │
                             ▼
                      Host OS (Ubuntu 24.04)
                      systemctl, apt/dpkg, journalctl, ip, ss, …
                      (no agent-initiated egress required)
```

### Why Grok + Ollama + MCP (under offline constraint)

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Agent host | Grok CLI **with project model override** | Local process; must be configured so sessions never call xAI for this repo |
| Models | Ollama on loopback | Weights and inference stay on host; Grok custom `base_url` |
| Tools | Local stdio MCP from **vendor/** or locked venv | No registry hits at startup; portable tool boundary |
| Knowledge | In-repo skills + docs | No web dependency for procedures |
| Policy | Project rules + permission modes | High blast radius; conservative defaults |

### Grok offline checklist

Project config must ensure:

1. `[models] default` is an Ollama model id only.
2. Every `[model.*]` used by this project points at `http://127.0.0.1:11434/v1` (not cloud).
3. No `fork_secondary_model` / secondary paths that resolve to cloud models for this workspace.
4. Project MCP set is a **closed allowlist** — do not inherit WAN-bound user MCP servers (e.g. Playwright pulling browsers, remote GitHub MCP) into the admin profile.
5. If Grok itself phones home for auth/telemetry, document it; prefer modes that work with local models without live xAI session **if the CLI supports that**. Validate during Phase 1; if a signed-in cloud session is required just to start the binary, treat that as a **blocker** and either configure offline/local-only mode or re-evaluate the harness.

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

**Removed from scope:** `@modelcontextprotocol/server-fetch` and any HTTP/SSE remote MCP. Web/CVE lookup is not a core capability.

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
- **No raw `run_shell` tool in v1.**
- **No tools whose primary purpose is outbound internet** (`curl` to WAN, `wget`, `pip install`, `npm install`, `docker pull`, `git fetch`).
- Package tools: prefer `dpkg-query`, `apt-cache` (local), `apt-get -s` simulate; document that applying upgrades needs reachable mirrors *as an OS fact*, not an agent dependency for diagnosis and planning from local state.

### 4.3 Tier C — Optional (Phase 3)

| Server | When | Offline rule |
|--------|------|--------------|
| Docker MCP | Docker present | Unix socket only; skills must not `docker pull` by default |
| Local Prometheus / node_exporter | If already on host | `127.0.0.1` scrape only |
| Playwright / GitHub / remote HTTP MCP | **Not in project profile** | Keep out of `.grok/config.toml` for this repo |

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

1. **Offline by default.** Do not use network tools, remote MCP, or cloud models. If a task truly requires internet (e.g. download a package with empty local cache), say so and stop — do not silently call the WAN.
2. **Read before write.** Inspect status/logs/config before changing anything.
3. **Plan for reversibility.** Prefer drop-ins, package holds, backups under staging.
4. **Stage then apply.** Propose diffs in-repo or `/tmp/linux-admin-staging`, then apply with approval.
5. **Prefer MCP admin tools** over ad-hoc shell when a specialized tool exists.
6. **Never** pipe remote content to a shell, disable security frameworks casually, or store secrets in the repo.
7. **Report impact:** change, rollback, verify.
8. **Local model awareness:** short tool results; summarize large logs.
9. **Knowledge source order:** in-repo skills/docs → local man pages (`man`, `/usr/share/doc`) → host state. Not the web.

### 5.2 Skills (repo-local only)

| Skill | Trigger | Behavior |
|-------|---------|----------|
| `diagnose-service` | service down/failing | status → journal → deps → config → fix plan |
| `package-update` | updates / upgrade | local upgradable list → simulate → apply if approved **and** mirrors available |
| `disk-pressure` | disk full | df/du → cleanup plan from local state |
| `network-diagnose` | local connectivity | addr, routes, ss, resolver config, firewall — works offline for local stack |
| `boot-health` | post-reboot failures | failed units, journal `-b -p err` |
| `harden-check` | security check | listening ports, failed SSH, local hardening state |

No skill may list “search the web” or “fetch CVE page” as a required step.

### 5.3 Permission posture

| Mode | Use |
|------|-----|
| Default interactive | Approve mutations |
| `always-approve` | **Forbidden** for production admin on this host |
| Headless / cron | Read-only MCP subset only |

Override any user-global `always-approve` for this project’s sessions.

---

## 6. Safe change workflow

```
1. Observe   → local MCP read tools
2. Hypothesize → agent explains root cause (local knowledge)
3. Propose   → staging / git
4. Review    → human diff + rollback
5. Apply     → gated MCP + sudo strategy
6. Verify    → local status/logs/smoke
7. Record    → local memory store + optional local git commit
```

### Sudo strategy

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| **A. Polkit / sudoers allowlist** (recommended) | NOPASSWD for specific commands | Auditable, least privilege | Careful sudoers design |
| **B. Interactive sudo** | Human runs printed commands | Safest | Less agentic |
| **C. Root agent** | Entire agent as root | Simple | **Rejected** as default |

Document in `docs/security.md`.

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
│   ├── doctor-offline.sh     # fail if egress required; simulate/check offline
│   └── sudoers.example
├── docs/
│   ├── architecture.md
│   ├── offline.md            # offline contract, test procedure
│   ├── mcp-servers.md
│   ├── ollama-models.md
│   └── security.md
└── tests/
    ├── mcp/
    └── offline/              # tests that mock/block network
```

`vendor/` may be gitignored if bootstrap is mandatory on each machine; then lockfiles **must** be committed and bootstrap must be deterministic. Prefer documenting both: “bootstrap once online, then airplane mode forever.”

---

## 8. Phased delivery

### Phase 0 — Repo & docs

- [x] `PLAN.md`, `README.md`, `.gitignore`
- [x] GitHub repo `krich11/linux-admin`
- [ ] Offline constraint documented (this revision)
- [ ] `docs/offline.md` outline in a follow-up PR

### Phase 1 — Local LLM + offline baseline MCP (1–2 days)

1. Install Ollama; pull models; **prove inference with WAN disabled**.
2. Project `.grok/config.toml`: **only** Ollama models; default = ollama-admin.
3. Vendor filesystem (and optional memory/git) MCP; wire absolute local commands.
4. `scripts/bootstrap.sh` + `scripts/doctor.sh` + `scripts/doctor-offline.sh`.
5. Smoke test full prompt loop offline.
6. Verify Grok does not require live cloud model access for this project session.

**Exit criteria:** Airplane-mode (or default route down) session can read allowlisted files and answer admin questions via Ollama; doctor-offline green.

### Phase 2 — Custom `linux-admin-mcp` (3–5 days)

1. Read-only tools (systemd, journal, df, ss).
2. Mutation tools + policy; no WAN tools.
3. Skills: diagnose-service, boot-health, network-diagnose (local).
4. Unit tests for allowlist + offline package tool behavior (graceful failure if apt cannot reach mirrors).

**Exit criteria:** Full local service diagnosis offline; restart only after approval.

### Phase 3 — Packages, hardening, polish (2–4 days)

1. Apt/dpkg tools with clear offline semantics.
2. package-update / disk-pressure skills.
3. Optional local Docker socket MCP (no pulls).
4. Headless read-only health report (cron-friendly, offline).

**Exit criteria:** Health report and dry-run package plan from local state without internet.

### Phase 4 — Hardening & ops (ongoing)

- Audit log `logs/agent-audit.jsonl` (local).
- Expand allowlists carefully; never add raw shell or WAN tools.
- Stronger local models as hardware allows.
- **No** cloud hybrid profile in this project. (Separate personal Grok config may still use cloud elsewhere; this repo’s config must not.)

---

## 9. Testing strategy

| Level | What |
|-------|------|
| Doctor | Ollama up, models on disk, MCP entrypoints exist and start |
| Doctor-offline | Drop default route or use network namespace; full smoke prompt; no process should need WAN |
| MCP unit | Allowlist rejects `bash -c`, `curl`, `docker pull`; caps output |
| Integration | Diagnose failed unit, list listeners, apt simulate from local cache |
| Regression | Golden tool-call transcripts |
| Safety | Writes outside allowlist fail; no network tools registered |

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
| Privilege escalation | Host compromise | No raw shell; sudoers allowlist; human approval |
| `/etc` corruption | Outage | Staging, diffs, drop-ins |
| Ollama down | Agent unusable | Doctor; **no cloud fallback** (fail closed, fix local) |
| `npx -y` / uvx at runtime | Offline failure + supply chain | Vendor + lockfiles; offline doctor asserts no registry access |
| Apt mirrors unreachable | Cannot install new packages | Expected; agent still diagnoses; report “needs mirror/cache” |
| Inherited user MCP (Playwright, GitHub) | Surprise egress | Project MCP closed set; document disabling WAN MCP for admin sessions |

---

## 11. Open decisions (Phase 1–2)

1. **Default Ollama model** after benchmarking on `phoenix`.
2. **Sudo strategy** A vs B (§6).
3. **`/etc` writes** via filesystem MCP vs apply-only tools.
4. **Vendor strategy:** commit `vendor/` vs bootstrap-only with lockfiles.
5. **Python vs Node** for `linux-admin-mcp` (recommend **Python + uv**).
6. **Grok offline auth:** confirm whether a live xAI session is required when using only custom Ollama models; document result in `docs/offline.md`.

---

## 12. Success metrics

- `doctor-offline.sh` green with no default route.
- Full tool-using admin session with WAN down (diagnose + stage + verified read-only report).
- Zero registered MCP tools that perform non-loopback network I/O by default.
- Zero unapproved host mutations in interactive mode.
- P95 Ollama tool-loop latency acceptable interactively (target &lt; 15s/step on chosen model).
- All custom MCP tools covered by allowlist unit tests including “no WAN binaries.”

---

## 13. Immediate next actions

1. Install Ollama; pull models; **airplane-mode inference test**.
2. Scaffold `.grok/config.toml` (Ollama-only), `AGENTS.md`, bootstrap + doctor + doctor-offline.
3. Vendor filesystem MCP; smoke test offline.
4. Scaffold `linux-admin-mcp` with `service_status` vertical slice.
5. Spike: Grok + Ollama with network disabled; record any cloud dependency.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Runtime network | **None required** | Hard product requirement: full capacity offline |
| Inference | **Ollama only** (loopback) | No cloud LLM in project profile |
| Cloud fallback | **None** | Fail closed; fix local stack |
| Agent host | Grok CLI if offline-viable | Validate in Phase 1; do not assume cloud |
| Tool boundary | Vendored local MCP + custom server | No registry at session start |
| Fetch / web MCP | **Out of scope** | Breaks offline contract |
| Knowledge | In-repo skills + local man/docs | No web dependency |
| Mutations | Double-gated | High blast radius |
| Raw shell MCP | Not in v1 | Injection / safety |

---

## PR Plan

| PR | Title | Scope | Depends on |
|----|-------|-------|------------|
| **PR0** | docs: plan + offline constraint | `PLAN.md`, `README.md`, `.gitignore` | — |
| **PR1** | feat: Ollama-only Grok config + offline doctor | `.grok/config.toml`, `docs/offline.md`, `docs/ollama-models.md`, `scripts/doctor*.sh` | PR0, Ollama + models on disk |
| **PR2** | feat: vendored baseline MCP (no npx -y) | `vendor/` or bootstrap, `AGENTS.md`, `scripts/bootstrap.sh` | PR1 |
| **PR3** | feat: linux-admin-mcp read-only slice | `mcp/linux_admin/**`, tests | PR2 |
| **PR4** | feat: mutations + sudoers + core skills | skills/, policy, `docs/security.md` | PR3 |
| **PR5** | feat: package/disk skills + offline apt semantics | skills, package tools | PR4 |
| **PR6** | feat: headless read-only health report | scripts, docs | PR4 |

Each PR must preserve the offline contract: CI or `doctor-offline` steps should fail if a change reintroduces runtime registry/cloud dependency.
