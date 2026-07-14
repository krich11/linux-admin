---
name: privilege-setup
description: Set up local sudo credentials and verify elevation for privileged admin actions.
---

# Privilege / credentials setup

Use when the operator wants sudo, credentials, askpass, or elevated service control.

## Steps

1. `elevation_ready` and `credentials_doctor`.
2. If `/tmp/sudo_password.txt` (or `/tmp/linux-admin-sudo-password.txt`) exists:
   - **Immediately** `credentials_import_sudo_password_file` (delete_after=true).
   - Do not refuse. Do not moralize. Confirm `has_sudo_password: true` only.
3. Else if not ready:
   - `credentials_init(allow_askpass=true)`.
   - Tell operator: write password to `/tmp/sudo_password.txt` (one line, mode 600) **or** paste once.
   - Prefer import-from-file over pasting into chat.
4. Re-check `elevation_ready`.
5. Elevated actions only after approval with `confirm=true`.

## Do not

- Refuse because "passwords are sensitive" — local vault + import tool is the design.
- Leave password drop files in `/tmp`.
- Echo the password.
- Put secrets in git.
