"""Systemd inspection and gated mutations."""

from __future__ import annotations

from linux_admin_mcp.elevate.runner import elevate_argv
from linux_admin_mcp.executil import run_argv


def list_failed_units() -> dict:
    r = run_argv(
        ["systemctl", "--failed", "--no-pager", "--plain"],
        timeout_sec=30,
    )
    return r.as_dict()


def service_status(unit: str) -> dict:
    unit = _sanitize_unit(unit)
    r = run_argv(
        ["systemctl", "status", unit, "--no-pager", "--full"],
        timeout_sec=30,
        max_bytes=100_000,
    )
    # status returns non-zero for inactive/failed — still useful
    return r.as_dict()


def service_show(unit: str) -> dict:
    unit = _sanitize_unit(unit)
    r = run_argv(
        ["systemctl", "show", unit, "--no-pager"],
        timeout_sec=30,
        max_bytes=100_000,
    )
    return r.as_dict()


def service_restart(unit: str, *, confirm: bool = False) -> dict:
    unit = _sanitize_unit(unit)
    er = elevate_argv(["systemctl", "restart", unit], confirm=confirm, timeout_sec=90)
    return er.as_dict()


def service_stop(unit: str, *, confirm: bool = False) -> dict:
    unit = _sanitize_unit(unit)
    er = elevate_argv(["systemctl", "stop", unit], confirm=confirm, timeout_sec=90)
    return er.as_dict()


def service_start(unit: str, *, confirm: bool = False) -> dict:
    unit = _sanitize_unit(unit)
    er = elevate_argv(["systemctl", "start", unit], confirm=confirm, timeout_sec=90)
    return er.as_dict()


def _sanitize_unit(unit: str) -> str:
    unit = (unit or "").strip()
    if not unit:
        raise ValueError("unit required")
    # basic injection guard: no spaces/metacharacters
    allowed = set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-:\\"
    )
    if any(c not in allowed for c in unit):
        raise ValueError(f"invalid unit name: {unit!r}")
    if len(unit) > 256:
        raise ValueError("unit name too long")
    return unit
