"""
files.security — Files the AI must never read
=============================================================
API keys, OAuth tokens, SSH keys and password stores are never indexed,
previewed, read by the agent or streamed to the UI, whatever the user's
"Hide from AI" settings say.
"""

from __future__ import annotations

from pathlib import Path

_SECRET_FILE_NAMES = {
    ".env", "credentials.json", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".netrc", ".pgpass",
    ".npmrc", ".pypirc", "known_hosts", "authorized_keys",
}
_SECRET_DIR_NAMES = {".ssh", ".gnupg", "keychains", ".aws", ".kube"}
# (.key is also Keynote, so private keys are caught by name/dir instead.)
_SECRET_SUFFIXES = {".pem", ".p12", ".pfx", ".kdbx", ".keychain", ".keychain-db"}

SECRET_FILE_REFUSAL = "Refused: “{name}” holds secrets (keys, tokens or passwords), so DeskMate will not read it."


def is_secret_path(path: Path) -> bool:
    name = path.name.lower()
    if name in _SECRET_FILE_NAMES or name.startswith(".env.") or (name.startswith("token_") and name.endswith(".json")):
        return True
    if path.suffix.lower() in _SECRET_SUFFIXES:
        return True
    return any(part.lower() in _SECRET_DIR_NAMES for part in path.parts)
