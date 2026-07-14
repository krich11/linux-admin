"""Host resource probes (read-only)."""

from __future__ import annotations

from linux_admin_mcp.executil import run_argv


def disk_df() -> dict:
    r = run_argv(["df", "-hT"])
    return r.as_dict()


def memory_free() -> dict:
    r = run_argv(["free", "-h"])
    return r.as_dict()


def loadavg() -> dict:
    r = run_argv(["uptime"])
    out = r.as_dict()
    try:
        with open("/proc/loadavg", encoding="utf-8") as f:
            out["loadavg_raw"] = f.read().strip()
    except OSError as e:
        out["loadavg_raw_error"] = str(e)
    return out


def host_identity() -> dict:
    h = run_argv(["hostname"])
    u = run_argv(["uname", "-a"])
    return {"hostname": h.as_dict(), "uname": u.as_dict()}
