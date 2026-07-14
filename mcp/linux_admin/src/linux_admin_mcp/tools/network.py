"""Local network diagnostics (no required WAN)."""

from __future__ import annotations

from linux_admin_mcp.executil import run_argv


def ip_addr() -> dict:
    r = run_argv(["ip", "-br", "addr"], timeout_sec=15)
    return r.as_dict()


def ip_route() -> dict:
    r = run_argv(["ip", "route"], timeout_sec=15)
    return r.as_dict()


def ss_listen() -> dict:
    r = run_argv(["ss", "-tulpn"], timeout_sec=20, max_bytes=150_000)
    return r.as_dict()
