"""Adaptive sudo runner: cached | nopasswd | askpass | tty | manual."""

from __future__ import annotations

import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from linux_admin_mcp.creds.store import CredentialStore, get_default_store
from linux_admin_mcp.executil import RunResult, resolve_binary, run_argv
from linux_admin_mcp.elevate.probe import probe_sudo


@dataclass
class ElevateResult:
    mode: str
    ok: bool
    result: RunResult | None
    message: str
    manual_command: list[str] | None = None

    def as_dict(self) -> dict:
        d = {
            "mode": self.mode,
            "ok": self.ok,
            "message": self.message,
            "manual_command": self.manual_command,
        }
        if self.result:
            d["result"] = self.result.as_dict()
        return d


def _askpass_path() -> str | None:
    # Prefer installed console script
    found = shutil.which("linux-admin-askpass")
    if found:
        return found
    # Fallback: run module with same interpreter
    return None


def elevate_argv(
    argv: Sequence[str],
    *,
    confirm: bool = False,
    timeout_sec: float = 60.0,
    store: CredentialStore | None = None,
    force_mode: str | None = None,
) -> ElevateResult:
    """
    Run allowlisted argv under sudo using adaptive policy.

    Mutations must pass confirm=True.
    """
    if not confirm:
        return ElevateResult(
            mode="denied",
            ok=False,
            result=None,
            message="confirm=true required for elevated execution",
        )
    if not argv:
        return ElevateResult(
            mode="denied", ok=False, result=None, message="empty argv"
        )

    # Validate target binary is allowlisted (not sudo itself as sole target misuse)
    try:
        target = resolve_binary(argv[0])
    except Exception as e:
        return ElevateResult(
            mode="denied", ok=False, result=None, message=f"target denied: {e}"
        )

    full_target = [str(target), *[str(a) for a in argv[1:]]]
    store = store or get_default_store()
    meta = store.load_meta()
    policy = (force_mode or (meta.sudo_policy if meta else "auto") or "auto").lower()

    if policy == "manual":
        cmd = ["sudo", "--", *full_target]
        return ElevateResult(
            mode="manual",
            ok=False,
            result=None,
            message="manual mode: run the command yourself, then retry",
            manual_command=cmd,
        )

    # Prefer passwordless if possible (unless forced to password/askpass/tty)
    probe = probe_sudo()
    if policy in ("auto", "nopasswd", "cached") and probe.get("sudo_n_ok"):
        r = run_argv(
            ["sudo", "-n", "--", *full_target],
            timeout_sec=timeout_sec,
        )
        mode = "nopasswd" if policy == "nopasswd" else "cached"
        return ElevateResult(
            mode=mode,
            ok=r.returncode == 0 and not r.timed_out,
            result=r,
            message="elevated with sudo -n",
        )

    if policy == "nopasswd":
        return ElevateResult(
            mode="denied",
            ok=False,
            result=None,
            message="sudo -n failed; policy is nopasswd (configure sudoers or change policy)",
        )

    # askpass path
    use_askpass = (
        policy in ("auto", "password", "askpass")
        and meta
        and meta.allow_askpass
        and store.get_sudo_password()
    )
    if use_askpass:
        askpass = _askpass_path()
        env = os.environ.copy()
        if askpass:
            env["SUDO_ASKPASS"] = askpass
            r = run_argv(
                ["sudo", "-A", "-n", "--", *full_target],
                timeout_sec=timeout_sec,
                env=env,
            )
            # Some sudo builds dislike -A with -n; retry -A only
            if r.returncode != 0:
                r = run_argv(
                    ["sudo", "-A", "--", *full_target],
                    timeout_sec=timeout_sec,
                    env=env,
                )
            return ElevateResult(
                mode="askpass",
                ok=r.returncode == 0 and not r.timed_out,
                result=r,
                message="elevated via SUDO_ASKPASS",
            )
        # module fallback
        askpass_mod = (
            f"{sys.executable} -c "
            f"'from linux_admin_mcp.elevate.askpass import main; main()'"
        )
        # Use a tiny wrapper script path written to XDG runtime if needed
        wrapper = _ensure_askpass_wrapper()
        env["SUDO_ASKPASS"] = wrapper
        r = run_argv(
            ["sudo", "-A", "--", *full_target],
            timeout_sec=timeout_sec,
            env=env,
        )
        return ElevateResult(
            mode="askpass",
            ok=r.returncode == 0 and not r.timed_out,
            result=r,
            message="elevated via SUDO_ASKPASS wrapper",
        )

    # TTY interactive sudo
    if policy in ("auto", "tty", "password") and sys.stdin.isatty() and sys.stdout.isatty():
        # Cannot use capture easily with interactive password; use subprocess without capture
        import subprocess

        try:
            proc = subprocess.run(
                ["sudo", "--", *full_target],
                timeout=timeout_sec,
                shell=False,
            )
            r = RunResult(
                argv=["sudo", "--", *full_target],
                returncode=proc.returncode,
                stdout="",
                stderr="",
                truncated=False,
            )
            return ElevateResult(
                mode="tty",
                ok=proc.returncode == 0,
                result=r,
                message="elevated via interactive TTY sudo",
            )
        except subprocess.TimeoutExpired:
            return ElevateResult(
                mode="tty",
                ok=False,
                result=None,
                message=f"sudo timed out after {timeout_sec}s",
            )

    # manual handoff
    cmd = ["sudo", "--", *full_target]
    return ElevateResult(
        mode="manual",
        ok=False,
        result=None,
        message=(
            "cannot elevate non-interactively: no sudo -n, no askpass secret, no TTY. "
            "Run the manual_command, or: linux-admin creds set-sudo && "
            "linux-admin creds set-policy --allow-askpass"
        ),
        manual_command=cmd,
    )


def _ensure_askpass_wrapper() -> str:
    """Write a 0700 askpass wrapper under XDG_RUNTIME_DIR or /tmp."""
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    base = Path(runtime) if runtime else Path("/tmp")
    path = base / f"linux-admin-askpass-{os.getuid()}.sh"
    content = (
        "#!/bin/sh\n"
        f'exec "{sys.executable}" -c '
        '"from linux_admin_mcp.elevate.askpass import main; main()"\n'
    )
    path.write_text(content, encoding="utf-8")
    os.chmod(path, 0o700)
    return str(path)
