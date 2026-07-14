"""Bounded argv-only subprocess runner (no shell)."""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

# Core allowlist: absolute resolution via PATH at call time for known basenames.
ALLOWED_BINARIES = frozenset(
    {
        "systemctl",
        "journalctl",
        "df",
        "free",
        "uptime",
        "ss",
        "ip",
        "hostname",
        "uname",
        "cat",
        "lsblk",
        "dpkg-query",
        "apt-cache",
        "apt-get",
        "who",
        "last",
        "id",
        "sudo",
        "true",
        "false",
    }
)

# Binaries never allowed (even if somehow resolved).
DENIED_BINARIES = frozenset(
    {
        "bash",
        "sh",
        "dash",
        "zsh",
        "fish",
        "curl",
        "wget",
        "nc",
        "ncat",
        "python",
        "python3",
        "perl",
        "ruby",
        "node",
        "npm",
        "npx",
        "docker",
        "podman",
        "ssh",
        "scp",
        "git",
    }
)

DEFAULT_TIMEOUT_SEC = 30
DEFAULT_MAX_BYTES = 200 * 1024


@dataclass
class RunResult:
    argv: list[str]
    returncode: int
    stdout: str
    stderr: str
    truncated: bool
    timed_out: bool = False

    def as_dict(self) -> dict:
        return {
            "argv": self.argv,
            "returncode": self.returncode,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "truncated": self.truncated,
            "timed_out": self.timed_out,
        }


def resolve_binary(name_or_path: str) -> Path:
    p = Path(name_or_path)
    if p.is_absolute():
        if not p.exists() or not os.access(p, os.X_OK):
            raise PermissionError(f"binary not executable: {p}")
        base = p.name
    else:
        base = name_or_path
        found = shutil.which(name_or_path)
        if not found:
            raise FileNotFoundError(f"binary not found on PATH: {name_or_path}")
        p = Path(found)

    if base in DENIED_BINARIES:
        raise PermissionError(f"binary denied: {base}")
    if base not in ALLOWED_BINARIES:
        raise PermissionError(f"binary not on allowlist: {base}")
    return p


def run_argv(
    argv: Sequence[str],
    *,
    timeout_sec: float = DEFAULT_TIMEOUT_SEC,
    max_bytes: int = DEFAULT_MAX_BYTES,
    env: Mapping[str, str] | None = None,
    cwd: str | Path | None = None,
    input_text: str | None = None,
) -> RunResult:
    if not argv:
        raise ValueError("empty argv")
    bin_path = resolve_binary(argv[0])
    full = [str(bin_path), *[str(a) for a in argv[1:]]]

    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    # Never inherit a poisoned SUDO_ASKPASS unless we set it deliberately.
    # Callers that need askpass pass it in env.

    try:
        proc = subprocess.run(
            full,
            capture_output=True,
            timeout=timeout_sec,
            env=run_env,
            cwd=str(cwd) if cwd else None,
            input=input_text.encode() if input_text is not None else None,
            shell=False,
        )
        stdout_b = proc.stdout or b""
        stderr_b = proc.stderr or b""
        truncated = False
        if len(stdout_b) > max_bytes:
            stdout_b = stdout_b[:max_bytes]
            truncated = True
        if len(stderr_b) > max_bytes:
            stderr_b = stderr_b[:max_bytes]
            truncated = True
        return RunResult(
            argv=full,
            returncode=proc.returncode,
            stdout=stdout_b.decode("utf-8", errors="replace"),
            stderr=stderr_b.decode("utf-8", errors="replace"),
            truncated=truncated,
        )
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"")[:max_bytes].decode("utf-8", errors="replace")
        err = (e.stderr or b"")[:max_bytes].decode("utf-8", errors="replace")
        return RunResult(
            argv=full,
            returncode=-1,
            stdout=out,
            stderr=err or f"timeout after {timeout_sec}s",
            truncated=True,
            timed_out=True,
        )
