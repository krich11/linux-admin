import pytest

from linux_admin_mcp.executil import DENIED_BINARIES, resolve_binary, run_argv


def test_denied_curl():
    with pytest.raises(PermissionError):
        resolve_binary("curl")


def test_denied_bash():
    with pytest.raises(PermissionError):
        resolve_binary("bash")


def test_systemctl_allowed():
    p = resolve_binary("systemctl")
    assert p.name == "systemctl"


def test_run_true():
    # true is allowlisted
    r = run_argv(["true"])
    assert r.returncode == 0


def test_denied_set_contains_network_tools():
    for b in ("curl", "wget", "npm", "npx", "docker"):
        assert b in DENIED_BINARIES
