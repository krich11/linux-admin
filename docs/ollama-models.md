# Ollama models

Default model weights: **`llama3.2:3b`** (small, reliable bootstrap default).  
Grok model ids: **`ollama-admin`**, **`ollama-fast`**.

## Grok config caveat

Grok loads **`[model.*]` only from `~/.grok/config.toml`**, not from project `.grok/config.toml`.  
Project config wires **MCP** only. Bootstrap runs `scripts/install-user-models.sh` to register models in the user config. The `linux-admin` launcher always starts with `-m ollama-admin`.

```bash
ollama serve   # if not already running
ollama pull llama3.2:3b
./scripts/install-user-models.sh
ollama list
grok models    # should list ollama-admin
```

Upgrade when hardware allows (edit **user** `~/.grok/config.toml` model sections, and pull weights):

| Weights | Grok id | Use |
|---------|---------|-----|
| `llama3.2:3b` | `ollama-admin` | Default / low VRAM |
| `qwen2.5-coder:7b` / `14b` | (custom) | Stronger tool use |
| `llama3.1:8b` | (custom) | General admin |

Always pull **before** going offline. Inference is loopback only: `http://127.0.0.1:11434/v1`.
