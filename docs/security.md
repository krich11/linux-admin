# Security model

## Trust boundaries

- Operator → Grok TUI (approvals)
- Grok → MCP tools (allowlisted argv)
- Elevate runner → sudo (adaptive mode)
- Credential store → keyring/file 0600 (never LLM)

## Rules

1. No raw shell MCP tool.
2. Binary allowlist in `executil.py`; denylist includes curl/wget/bash/etc.
3. Mutations require `confirm=true`.
4. Prefer `sudo -n` to avoid hung password prompts.
5. Askpass only when `allow_askpass` is explicitly enabled.
6. Audit-friendly results include `mode` but never secrets.

## Optional sudoers

See `scripts/sudoers.example`. Install only after review.
