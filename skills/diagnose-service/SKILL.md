---
name: diagnose-service
description: Diagnose a failing or unhealthy systemd service using local tools only.
---

# Diagnose service

## Steps

1. `service_status` on the unit (e.g. `nginx.service`).
2. `list_failed_units` for related failures.
3. `journal_since` with `unit=<name>` and `since=1 hour ago` (or boot).
4. `service_show` if unit file / deps unclear.
5. Summarize root cause hypothesis and safe next actions.
6. Only if the operator approves: `service_restart` with `confirm=true`.

## Stop conditions

- Unit name unknown after listing failed units — ask the operator.
- Elevation returns `manual` — print command and wait.

## Offline

Do not require web search. Optional online enrichment only after local diagnosis.
