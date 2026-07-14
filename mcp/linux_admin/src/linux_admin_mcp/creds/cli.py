"""CLI: linux-admin-creds — manage per-host credentials (no secrets on argv)."""

from __future__ import annotations

import argparse
import getpass
import json
import sys

from .store import CredentialStore, get_default_store


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="linux-admin-creds",
        description="Per-host credential repository for linux-admin (secrets never printed).",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init", help="Initialize host binding and policy")
    p_init.add_argument(
        "--policy",
        default="auto",
        choices=["auto", "nopasswd", "password", "tty", "manual"],
    )
    p_init.add_argument(
        "--backend",
        default="file",
        choices=["file", "keyring", "metadata"],
    )
    p_init.add_argument(
        "--allow-askpass",
        action="store_true",
        help="Allow SUDO_ASKPASS automation when a password is stored",
    )

    sub.add_parser("status", help="Show non-secret status for this host")

    p_set = sub.add_parser(
        "set-sudo",
        help="Store sudo password (prompt on TTY; never pass on command line)",
    )
    p_set.add_argument(
        "--stdin",
        action="store_true",
        help="Read password from stdin (operator-controlled pipe only)",
    )

    sub.add_parser("clear-sudo", help="Delete stored sudo password")

    p_pol = sub.add_parser("set-policy", help="Update sudo policy / askpass flag")
    p_pol.add_argument(
        "--policy",
        choices=["auto", "nopasswd", "password", "tty", "manual"],
    )
    p_pol.add_argument("--allow-askpass", action="store_true", default=None)
    p_pol.add_argument("--deny-askpass", action="store_true")

    sub.add_parser("doctor", help="Report elevation readiness (no secrets)")

    args = parser.parse_args(argv)
    store = get_default_store()

    if args.cmd == "init":
        meta = store.init(
            sudo_policy=args.policy,
            backend=args.backend,
            allow_askpass=args.allow_askpass,
        )
        print(json.dumps(meta.public_dict(), indent=2))
        return

    if args.cmd == "status":
        print(json.dumps(store.status(), indent=2))
        return

    if args.cmd == "set-sudo":
        if args.stdin:
            password = sys.stdin.read().rstrip("\n")
        else:
            if not sys.stdin.isatty():
                print(
                    "error: no TTY; re-run interactively or use --stdin",
                    file=sys.stderr,
                )
                sys.exit(2)
            password = getpass.getpass("sudo password for this host: ")
            confirm = getpass.getpass("confirm: ")
            if password != confirm:
                print("error: passwords do not match", file=sys.stderr)
                sys.exit(1)
        store.set_sudo_password(password)
        print(json.dumps({"ok": True, "has_sudo_password": True}, indent=2))
        return

    if args.cmd == "clear-sudo":
        store.clear_sudo_password()
        print(json.dumps({"ok": True, "has_sudo_password": False}, indent=2))
        return

    if args.cmd == "set-policy":
        allow = None
        if args.deny_askpass:
            allow = False
        elif args.allow_askpass:
            allow = True
        meta = store.set_policy(sudo_policy=args.policy, allow_askpass=allow)
        print(json.dumps(meta.public_dict(), indent=2))
        return

    if args.cmd == "doctor":
        from linux_admin_mcp.elevate.probe import probe_sudo

        st = store.status()
        probe = probe_sudo()
        out = {
            "credentials": st,
            "sudo_probe": probe,
            "recommendation": _recommend(st, probe),
        }
        print(json.dumps(out, indent=2))
        return


def _recommend(st: dict, probe: dict) -> str:
    if probe.get("sudo_n_ok"):
        return "sudo -n works (nopasswd or cached ticket); no password store required"
    if st.get("has_sudo_password") and st.get("allow_askpass"):
        return "askpass mode available for headless elevation"
    if st.get("has_sudo_password"):
        return "password stored but allow_askpass is false; enable with set-policy --allow-askpass or use TTY"
    return "store a password (set-sudo) or use interactive TTY / configure NOPASSWD sudoers"


if __name__ == "__main__":
    main()
