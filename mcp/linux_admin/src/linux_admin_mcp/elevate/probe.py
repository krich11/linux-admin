"""Probe whether passwordless sudo currently works."""

from __future__ import annotations

from linux_admin_mcp.executil import run_argv


def probe_sudo(*, timeout_sec: float = 5.0) -> dict:
    """Return whether `sudo -n true` succeeds (NOPASSWD or valid timestamp)."""
    try:
        r = run_argv(["sudo", "-n", "true"], timeout_sec=timeout_sec, max_bytes=4096)
        return {
            "sudo_n_ok": r.returncode == 0,
            "returncode": r.returncode,
            "stderr": (r.stderr or "")[:500],
            "timed_out": r.timed_out,
        }
    except Exception as e:
        return {
            "sudo_n_ok": False,
            "error": str(e),
        }
