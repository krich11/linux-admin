"""Per-host credential repository."""

from .store import CredentialStore, get_default_store

__all__ = ["CredentialStore", "get_default_store"]
