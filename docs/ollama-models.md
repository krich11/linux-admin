# Ollama models

Default project model: **`llama3.2:3b`** (small, reliable bootstrap default).

```bash
ollama serve   # if not already running
ollama pull llama3.2:3b
ollama list
```

Upgrade when hardware allows (edit `.grok/config.toml`):

| Model | Use |
|-------|-----|
| `llama3.2:3b` | Default / low VRAM |
| `qwen2.5-coder:7b` / `14b` | Stronger tool use |
| `llama3.1:8b` | General admin |

Always pull **before** going offline. Inference is loopback only: `http://127.0.0.1:11434/v1`.
