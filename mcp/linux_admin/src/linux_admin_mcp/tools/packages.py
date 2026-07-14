"""Package inspection with offline-friendly semantics."""

from __future__ import annotations

from linux_admin_mcp.executil import run_argv


def dpkg_list_installed(*, pattern: str = "") -> dict:
    argv = ["dpkg-query", "-W", "-f=${Package}\\t${Version}\\t${Status}\\n"]
    r = run_argv(argv, timeout_sec=60, max_bytes=200_000)
    out = r.as_dict()
    if pattern and r.returncode == 0:
        lines = [ln for ln in r.stdout.splitlines() if pattern in ln]
        out["stdout"] = "\n".join(lines[:500])
        out["filtered"] = True
        out["match_count"] = len(lines)
    return out


def apt_list_upgradable() -> dict:
    """
    List upgradable packages from local cache.
    May be empty or stale if `apt update` has not been run; does not require WAN
    for the query itself (apt-get may still try network on some systems — we use cache).
    """
    r = run_argv(
        ["apt-get", "-s", "upgrade"],
        timeout_sec=120,
        max_bytes=200_000,
    )
    out = r.as_dict()
    out["note"] = (
        "Simulation from local apt state. If indexes are stale or mirrors "
        "unreachable, results may be incomplete — that is expected offline."
    )
    return out


def apt_cache_policy(package: str) -> dict:
    package = package.strip()
    if not package or any(c in package for c in " \t\n;|&$`"):
        raise ValueError("invalid package name")
    r = run_argv(["apt-cache", "policy", package], timeout_sec=30)
    return r.as_dict()
