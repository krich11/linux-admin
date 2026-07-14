"""Stable host identity for credential partitioning."""

from __future__ import annotations

import os
import socket
from pathlib import Path


def machine_id() -> str:
    for path in (Path("/etc/machine-id"), Path("/var/lib/dbus/machine-id")):
        try:
            text = path.read_text(encoding="utf-8").strip()
            if text:
                return text
        except OSError:
            continue
    # Fallback: hostname only (weaker)
    return f"hostname:{socket.gethostname()}"


def hostname() -> str:
    try:
        return socket.getfqdn() or socket.gethostname()
    except OSError:
        return socket.gethostname()


def username() -> str:
    return os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
