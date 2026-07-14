"""Credential store: metadata + optional secret backends.

Secret values are never returned via status/list APIs.
"""

from __future__ import annotations

import json
import os
import stat
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Literal

from .host_id import hostname, machine_id, username

SudoPolicy = Literal["auto", "nopasswd", "password", "tty", "manual"]
BackendName = Literal["keyring", "file", "metadata"]


def data_root() -> Path:
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg) / "linux-admin"
    return Path.home() / ".local" / "share" / "linux-admin"


@dataclass
class HostMeta:
    host_id: str
    hostname: str
    username: str
    sudo_policy: SudoPolicy = "auto"
    allow_askpass: bool = False
    backend: BackendName = "file"
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    has_sudo_password: bool = False  # metadata only

    def public_dict(self) -> dict[str, Any]:
        d = asdict(self)
        # never include secrets
        return d


class CredentialStore:
    def __init__(self, root: Path | None = None, host_id: str | None = None) -> None:
        self.root = root or data_root()
        self.host_id = host_id or machine_id()
        self.host_dir = self.root / "hosts" / self.host_id
        self.meta_path = self.host_dir / "meta.json"
        self.secret_path = self.host_dir / "sudo_password.secret"

    def ensure_host_dir(self) -> None:
        self.host_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.host_dir, 0o700)

    def load_meta(self) -> HostMeta | None:
        if not self.meta_path.exists():
            return None
        data = json.loads(self.meta_path.read_text(encoding="utf-8"))
        return HostMeta(
            host_id=data["host_id"],
            hostname=data.get("hostname", hostname()),
            username=data.get("username", username()),
            sudo_policy=data.get("sudo_policy", "auto"),
            allow_askpass=bool(data.get("allow_askpass", False)),
            backend=data.get("backend", "file"),
            created_at=float(data.get("created_at", time.time())),
            updated_at=float(data.get("updated_at", time.time())),
            has_sudo_password=bool(data.get("has_sudo_password", False)),
        )

    def save_meta(self, meta: HostMeta) -> None:
        self.ensure_host_dir()
        meta.updated_at = time.time()
        # Re-check secret presence for accuracy
        meta.has_sudo_password = self._secret_exists(meta.backend)
        text = json.dumps(meta.public_dict(), indent=2, sort_keys=True) + "\n"
        self.meta_path.write_text(text, encoding="utf-8")
        os.chmod(self.meta_path, 0o600)

    def init(
        self,
        *,
        sudo_policy: SudoPolicy = "auto",
        backend: BackendName = "file",
        allow_askpass: bool = False,
    ) -> HostMeta:
        existing = self.load_meta()
        if existing and existing.host_id != self.host_id:
            raise RuntimeError("host_id mismatch; refuse to rebind without clear")
        meta = HostMeta(
            host_id=self.host_id,
            hostname=hostname(),
            username=username(),
            sudo_policy=sudo_policy,
            allow_askpass=allow_askpass,
            backend=backend,
            created_at=existing.created_at if existing else time.time(),
        )
        # Prefer keyring if available and requested
        if backend == "keyring" and not self._keyring_available():
            meta.backend = "file"
        self.save_meta(meta)
        return meta

    def status(self) -> dict[str, Any]:
        meta = self.load_meta()
        if not meta:
            return {
                "initialized": False,
                "host_id": self.host_id,
                "hostname": hostname(),
                "username": username(),
                "data_root": str(self.root),
            }
        d = meta.public_dict()
        d["initialized"] = True
        d["data_root"] = str(self.root)
        d["has_sudo_password"] = self._secret_exists(meta.backend)
        # Never include secret material
        assert "password" not in d
        assert "secret" not in d
        return d

    def set_sudo_password(self, password: str) -> None:
        if not password:
            raise ValueError("empty password")
        meta = self.load_meta() or self.init()
        if meta.backend == "keyring" and self._keyring_available():
            self._keyring_set(password)
        else:
            meta.backend = "file"
            self.ensure_host_dir()
            self.secret_path.write_text(password, encoding="utf-8")
            os.chmod(self.secret_path, 0o600)
            # verify mode
            mode = stat.S_IMODE(self.secret_path.stat().st_mode)
            if mode != 0o600:
                os.chmod(self.secret_path, 0o600)
        meta.has_sudo_password = True
        self.save_meta(meta)

    def get_sudo_password(self) -> str | None:
        """Internal use only (askpass / elevate). Never expose via MCP tool results."""
        meta = self.load_meta()
        if not meta:
            return None
        if meta.backend == "keyring" and self._keyring_available():
            return self._keyring_get()
        if self.secret_path.exists():
            return self.secret_path.read_text(encoding="utf-8").rstrip("\n")
        return None

    def clear_sudo_password(self) -> None:
        meta = self.load_meta()
        if self.secret_path.exists():
            self.secret_path.unlink()
        if self._keyring_available():
            try:
                self._keyring_delete()
            except Exception:
                pass
        if meta:
            meta.has_sudo_password = False
            self.save_meta(meta)

    def set_policy(
        self,
        *,
        sudo_policy: SudoPolicy | None = None,
        allow_askpass: bool | None = None,
    ) -> HostMeta:
        meta = self.load_meta() or self.init()
        if sudo_policy is not None:
            meta.sudo_policy = sudo_policy
        if allow_askpass is not None:
            meta.allow_askpass = allow_askpass
        self.save_meta(meta)
        return meta

    def _secret_exists(self, backend: BackendName) -> bool:
        if backend == "keyring" and self._keyring_available():
            return bool(self._keyring_get())
        return self.secret_path.exists() and self.secret_path.stat().st_size > 0

    def _keyring_service(self) -> str:
        return "linux-admin"

    def _keyring_account(self) -> str:
        return f"sudo:{self.host_id}:{username()}"

    def _keyring_available(self) -> bool:
        try:
            import keyring  # noqa: F401

            return True
        except ImportError:
            return False

    def _keyring_set(self, password: str) -> None:
        import keyring

        keyring.set_password(self._keyring_service(), self._keyring_account(), password)

    def _keyring_get(self) -> str | None:
        import keyring

        return keyring.get_password(self._keyring_service(), self._keyring_account())

    def _keyring_delete(self) -> None:
        import keyring

        try:
            keyring.delete_password(self._keyring_service(), self._keyring_account())
        except keyring.errors.PasswordDeleteError:
            pass


def get_default_store() -> CredentialStore:
    return CredentialStore()
