# Ollama models

Inference is on the **LAN Ollama host**, not a private model repo inside this git project.

## Endpoint (this deployment)

| Setting | Default |
|---------|---------|
| Server | `http://192.168.200.120:11434` |
| Config file | `config/ollama.env` |
| Admin weights | `qwen2.5-coder:7b` |
| Fast weights | `llama3.2:3b` |
| Grok model ids | `ollama-admin`, `ollama-fast` |

Override:

```bash
export OLLAMA_BASE_URL=http://192.168.200.120:11434
export OLLAMA_ADMIN_MODEL=qwen2.5-coder:14b-base-q4_0
./scripts/install-user-models.sh
```

## Grok config caveat

Grok loads **`[model.*]` only from `~/.grok/config.toml`**. Project `.grok/config.toml` wires **MCP** only.

```bash
./scripts/install-user-models.sh   # writes base_url + model tags into user config
curl -s http://192.168.200.120:11434/api/tags | head
grok models                        # should list ollama-admin
```

Models are pulled and stored **on the Ollama server** (`192.168.200.120`), not in this repository.

## Suggested tags (already on the remote library)

| Role | Tag |
|------|-----|
| Admin / tools (default) | `qwen2.5-coder:7b` |
| Stronger coding | `qwen2.5-coder:14b-base-q4_0`, `qwen2.5:14b` |
| General | `llama3.1:8b`, `hermes3:8b` |
| Small / fast | `llama3.2:3b`, `qwen2.5:3b` |
