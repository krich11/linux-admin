"""Adaptive sudo elevation."""

from .runner import ElevateResult, elevate_argv
from .probe import probe_sudo

__all__ = ["elevate_argv", "ElevateResult", "probe_sudo"]
