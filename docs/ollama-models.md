# Ollama models

## Why `/model` / last-used works

`linux-admin` **does not pass `-m` on interactive launch**, so Grok keeps:

1. The model you last used in the TUI (`/model`, Ctrl+M), or  
2. `[models].default` from `~/.grok/config.toml` (set once at **bootstrap** to `ollama-admin`)

Force a model only when you want to:

```bash
LINUX_ADMIN_MODEL=ollama-local linux-admin
LINUX_ADMIN_MODEL=ollama-admin linux-admin -p "…"
```

Headless (`-p`) still auto-picks primary vs local if you do not set `LINUX_ADMIN_MODEL`, because there is no sticky interactive session.

## Primary — LAN Ollama (T4 16GB)

| Setting | Value |
|---------|--------|
| URL | `http://192.168.200.120:11434` |
| Grok id | `ollama-admin` |
| Weights | **Auto-picked at bootstrap** for T4 (see below) |

```bash
linux-admin bootstrap          # re-pick + register + set default once
linux-admin pick-model         # show ranking only
./scripts/install-user-models.sh --pick --set-default
```

Picker rules (`scripts/pick-admin-model.py`):

- Blob ≲ 10 GB (room for KV/context on 16 GB T4)
- Prefer ~12–15B instruct Q4 models (quality)
- Prefer modern families (Qwen2.5, etc.) and coding/instruct tags
- Skip embeddings, image toys, and pure `:base` checkpoints

## Fallback — local

| Grok id | URL | Weights |
|---------|-----|---------|
| `ollama-local` | `127.0.0.1:11434` | `llama3.2:3b` |

```bash
linux-admin ensure-local
```

## Also registered

| Grok id | Role |
|---------|------|
| `ollama-fast` | Smaller LAN model for quick turns |
| `ollama-local` | Break-glass on this machine |
