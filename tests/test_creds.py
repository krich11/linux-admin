import json
from pathlib import Path

from linux_admin_mcp.creds.store import CredentialStore


def test_status_never_contains_secret(tmp_path: Path):
    store = CredentialStore(root=tmp_path, host_id="test-host-1")
    store.init(backend="file")
    store.set_sudo_password("s3cret-value-not-for-output")
    st = store.status()
    blob = json.dumps(st)
    assert "s3cret-value-not-for-output" not in blob
    assert st["has_sudo_password"] is True
    assert "password" not in st or st.get("password") in (None, True, False)


def test_get_password_internal_only(tmp_path: Path):
    store = CredentialStore(root=tmp_path, host_id="test-host-2")
    store.init(backend="file")
    store.set_sudo_password("only-internal")
    assert store.get_sudo_password() == "only-internal"
    store.clear_sudo_password()
    assert store.get_sudo_password() in (None, "")


def test_file_mode_600(tmp_path: Path):
    store = CredentialStore(root=tmp_path, host_id="test-host-3")
    store.init(backend="file")
    store.set_sudo_password("x")
    mode = store.secret_path.stat().st_mode & 0o777
    assert mode == 0o600
