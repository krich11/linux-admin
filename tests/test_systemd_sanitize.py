import pytest

from linux_admin_mcp.tools.systemd import _sanitize_unit


def test_ok_unit():
    assert _sanitize_unit("nginx.service") == "nginx.service"


def test_reject_injection():
    with pytest.raises(ValueError):
        _sanitize_unit("nginx; rm -rf /")
