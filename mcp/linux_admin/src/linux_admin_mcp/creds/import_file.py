"""Import sudo password from an allowlisted drop file (no LLM secret handling)."""

from __future__ import annotations

import os
import stat
from pathlib import Path

from .store import CredentialStore, get_default_store

# Paths the agent / operator may use as a one-shot drop.
ALLOWED_BASENAMES = frozenset(
    {
        "sudo_password.txt",
        "linux-admin-sudo-password",
        "linux-admin-sudo-password.txt",
    }
)

ALLOWED_DIR_PREFIXES = (
    Path("/tmp"),
    Path("/var/tmp"),
)


def _is_allowed_path(path: Path) -> bool:
    try:
        resolved = path.resolve()
    except OSError:
        return False
    if resolved.name not in ALLOWED_BASENAMES and not resolved.name.startswith(
        "linux-admin-sudo-"
    ):
        # also allow exact /tmp/sudo_password.txt style already covered by basename
        if resolved.name not in ALLOWED_BASENAMES:
            return False
    for prefix in ALLOWED_DIR_PREFIXES:
        try:
            resolved.relative_to(prefix.resolve())
            return True
        except ValueError:
            continue
    # XDG runtime
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        try:
            resolved.relative_to(Path(runtime).resolve())
            return resolved.name.startswith("linux-admin-sudo") or resolved.name in ALLOWED_BASENAMES
        except ValueError:
            pass
    return False


def secure_unlink(path: Path) -> None:
    """Best-effort overwrite + unlink."""
    try:
        if path.is_file():
            size = path.stat().st_size
            with open(path, "r+b", buffering=0) as f:
                f.write(b"\0" * max(size, 1))
                f.flush()
                os.fsync(f.fileno())
            path.unlink(missing_ok=True)
    except OSError:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


def import_sudo_password_file(
    path: str | Path,
    *,
    allow_askpass: bool = True,
    delete_after: bool = True,
    store: CredentialStore | None = None,
) -> dict:
    """
    Read password from allowlisted path, store it, optionally wipe file.
    Never returns the password value.
    """
    p = Path(path).expanduser()
    if not _is_allowed_path(p):
        return {
            "ok": False,
            "error": f"path not allowlisted for password import: {p}",
            "hint": "Use /tmp/sudo_password.txt or /tmp/linux-admin-sudo-password.txt",
        }
    if not p.is_file():
        return {"ok": False, "error": f"file not found: {p}"}

    try:
        mode = stat.S_IMODE(p.stat().st_mode)
        raw = p.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return {"ok": False, "error": str(e)}

    # first line only; strip whitespace/newlines
    password = raw.splitlines()[0].strip() if raw else ""
    if not password:
        if delete_after:
            secure_unlink(p)
        return {"ok": False, "error": "file empty after trim"}

    store = store or get_default_store()
    if store.load_meta() is None:
        store.init(sudo_policy="auto", backend="file", allow_askpass=allow_askpass)
    store.set_sudo_password(password)
    if allow_askpass:
        store.set_policy(allow_askpass=True)

    # Drop reference
    password = ""
    raw = ""

    deleted = False
    if delete_after:
        secure_unlink(p)
        deleted = not p.exists()

    st = store.status()
    return {
        "ok": True,
        "has_sudo_password": st.get("has_sudo_password"),
        "allow_askpass": st.get("allow_askpass"),
        "sudo_policy": st.get("sudo_policy"),
        "source_path": str(p),
        "source_mode_was": oct(mode),
        "deleted_source": deleted,
        "message": (
            "sudo password imported into local credential store; "
            "source file wiped if delete_after. Password value never returned."
        ),
    }
