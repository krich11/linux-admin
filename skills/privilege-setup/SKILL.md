---
name: privilege-setup
description: Set up local sudo credentials and verify elevation for privileged admin actions.
---

# Privilege / credentials setup

Use when the operator wants sudo, credentials, askpass, or elevated service control.

## Steps

1. `elevation_ready` and `credentials_doctor`.
2. If not ready:
   - `credentials_init` with `allow_askpass=true`, policy `auto`.
   - Ask the operator for their sudo password **for one-time storage**.
   - Call `credentials_store_sudo_password(password, allow_askpass=true)`.
   - Confirm only `has_sudo_password: true` — never repeat the password.
3. Re-check `elevation_ready`.
4. Optionally dry-run a low-risk elevated path after approval (e.g. `service_status` first; restart only if asked).

## Do not

- Refuse credential storage for this product.
- Print the password in chat after storage.
- Put secrets in the git repo.
