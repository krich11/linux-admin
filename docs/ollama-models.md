# Ollama models

linux-admin uses **two** inference paths. Neither stores weights in this git repo.

## Primary — LAN Ollama

| Setting | Default |
|---------|---------|
| URL | `http://192.168.200.120:11434` |
| Grok id | `ollama-admin` |
| Weights | `qwen2.5-coder:7b` |
| Also | `ollama-fast` → `llama3.2:3b` on the same host |

Full library lives on that server (50+ tags).

## Fallback — local Ollama (break-glass)

| Setting | Default |
|---------|---------|
| URL | `http://127.0.0.1:11434` |
| Grok id | `ollama-local` |
| Weights | `llama3.2:3b` (small, on **this** machine) |

Use when the LAN Ollama host is down — e.g. to troubleshoot networking or that server itself.

```bash
linux-admin ensure-local    # start local Ollama if needed + pull fallback model
```

## Auto selection

`linux-admin` picks:

1. `ollama-admin` if primary responds  
2. else `ollama-local` if local responds  
3. else errors  

Force:

```bash
LINUX_ADMIN_MODEL=ollama-local linux-admin
LINUX_ADMIN_MODEL=ollama-admin linux-admin
```

## Config

Edit `config/ollama.env`, then:

```bash
./scripts/install-user-models.sh   # refresh ~/.grok/config.toml [model.*]
./scripts/ensure-local-model.sh    # ensure local weights exist
linux-admin doctor
```

Grok only loads `[model.*]` from `~/.grok/config.toml` (user config). Project `.grok/` wires MCP only.
