from linux_admin_mcp.elevate.runner import elevate_argv


def test_confirm_required():
    er = elevate_argv(["true"], confirm=False)
    assert er.ok is False
    assert er.mode == "denied"


def test_manual_policy(tmp_path, monkeypatch):
    from linux_admin_mcp.creds.store import CredentialStore

    store = CredentialStore(root=tmp_path, host_id="elev-1")
    store.init(sudo_policy="manual", backend="metadata")
    er = elevate_argv(["true"], confirm=True, store=store)
    assert er.mode == "manual"
    assert er.manual_command is not None
    assert er.manual_command[0] == "sudo"
