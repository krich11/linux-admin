"""SUDO_ASKPASS helper — prints stored password once; never logs it."""

from __future__ import annotations

import sys


def main() -> None:
    # Late import to keep cold path light
    from linux_admin_mcp.creds.store import get_default_store

    store = get_default_store()
    meta = store.load_meta()
    if not meta or not meta.allow_askpass:
        # Refuse if askpass not explicitly allowed
        print("askpass not allowed for this host", file=sys.stderr)
        sys.exit(1)
    pw = store.get_sudo_password()
    if not pw:
        print("no sudo password stored", file=sys.stderr)
        sys.exit(1)
    # sudo reads password from stdout
    sys.stdout.write(pw)
    if not pw.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()
    sys.exit(0)


if __name__ == "__main__":
    main()
