"""Journal queries with caps."""

from __future__ import annotations

from linux_admin_mcp.executil import run_argv


def journal_since(
    *,
    since: str = "1 hour ago",
    unit: str | None = None,
    priority: str | None = None,
    lines: int = 100,
) -> dict:
    lines = max(1, min(int(lines), 500))
    argv = [
        "journalctl",
        "--no-pager",
        "-o",
        "short-iso",
        "-n",
        str(lines),
        "--since",
        since,
    ]
    if unit:
        argv.extend(["-u", unit])
    if priority:
        argv.extend(["-p", priority])
    r = run_argv(argv, timeout_sec=45, max_bytes=150_000)
    return r.as_dict()


def boot_errors(*, lines: int = 80) -> dict:
    lines = max(1, min(int(lines), 500))
    r = run_argv(
        [
            "journalctl",
            "-b",
            "-p",
            "err",
            "--no-pager",
            "-o",
            "short-iso",
            "-n",
            str(lines),
        ],
        timeout_sec=45,
        max_bytes=150_000,
    )
    return r.as_dict()
