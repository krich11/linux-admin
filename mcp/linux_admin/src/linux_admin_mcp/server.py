"""MCP stdio server exposing linux-admin tools."""

from __future__ import annotations

import json
from typing import Any

from mcp.server.fastmcp import FastMCP

from linux_admin_mcp import __version__
from linux_admin_mcp.creds.store import get_default_store
from linux_admin_mcp.elevate.probe import probe_sudo
from linux_admin_mcp.tools import journal, network, packages, resources, systemd

mcp = FastMCP(
    "linux-admin",
    instructions=(
        "Local-first Linux admin tools. Prefer these over ad-hoc shell. "
        "Mutations require confirm=true. Never request sudo passwords in chat; "
        "use credential store / elevation modes. Core path works offline."
    ),
)


def _j(data: Any) -> str:
    return json.dumps(data, indent=2, default=str)


@mcp.tool()
def host_identity() -> str:
    """Hostname and uname for this machine."""
    return _j(resources.host_identity())


@mcp.tool()
def disk_df() -> str:
    """Disk free space (df -hT)."""
    return _j(resources.disk_df())


@mcp.tool()
def memory_free() -> str:
    """Memory usage (free -h)."""
    return _j(resources.memory_free())


@mcp.tool()
def loadavg() -> str:
    """Load average / uptime."""
    return _j(resources.loadavg())


@mcp.tool()
def list_failed_units() -> str:
    """List failed systemd units."""
    return _j(systemd.list_failed_units())


@mcp.tool()
def service_status(unit: str) -> str:
    """systemctl status for a unit (e.g. ssh.service, nginx.service)."""
    return _j(systemd.service_status(unit))


@mcp.tool()
def service_show(unit: str) -> str:
    """systemctl show properties for a unit."""
    return _j(systemd.service_show(unit))


@mcp.tool()
def service_restart(unit: str, confirm: bool = False) -> str:
    """Restart a systemd unit via adaptive sudo. Requires confirm=true."""
    return _j(systemd.service_restart(unit, confirm=confirm))


@mcp.tool()
def service_start(unit: str, confirm: bool = False) -> str:
    """Start a systemd unit via adaptive sudo. Requires confirm=true."""
    return _j(systemd.service_start(unit, confirm=confirm))


@mcp.tool()
def service_stop(unit: str, confirm: bool = False) -> str:
    """Stop a systemd unit via adaptive sudo. Requires confirm=true."""
    return _j(systemd.service_stop(unit, confirm=confirm))


@mcp.tool()
def journal_since(
    since: str = "1 hour ago",
    unit: str | None = None,
    priority: str | None = None,
    lines: int = 100,
) -> str:
    """Query journald since a time expression. Optional unit and priority (e.g. err)."""
    return _j(
        journal.journal_since(
            since=since, unit=unit, priority=priority, lines=lines
        )
    )


@mcp.tool()
def boot_errors(lines: int = 80) -> str:
    """Current-boot journal messages at priority err or worse."""
    return _j(journal.boot_errors(lines=lines))


@mcp.tool()
def ip_addr() -> str:
    """Brief IP address list (local)."""
    return _j(network.ip_addr())


@mcp.tool()
def ip_route() -> str:
    """IP routing table (local)."""
    return _j(network.ip_route())


@mcp.tool()
def ss_listen() -> str:
    """Listening sockets (ss -tulpn)."""
    return _j(network.ss_listen())


@mcp.tool()
def dpkg_list(pattern: str = "") -> str:
    """List installed packages (optional substring filter). Offline-friendly."""
    return _j(packages.dpkg_list_installed(pattern=pattern))


@mcp.tool()
def apt_list_upgradable() -> str:
    """Simulate upgrade from local apt state (may be stale offline)."""
    return _j(packages.apt_list_upgradable())


@mcp.tool()
def apt_cache_policy(package: str) -> str:
    """Show apt-cache policy for one package."""
    return _j(packages.apt_cache_policy(package))


@mcp.tool()
def credentials_status() -> str:
    """Non-secret credential store status for this host (never returns passwords)."""
    return _j(get_default_store().status())


@mcp.tool()
def sudo_probe() -> str:
    """Probe whether passwordless sudo (-n) currently works."""
    return _j(probe_sudo())


def main() -> None:
    # stdio transport for Grok MCP
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
