"""api.fs — Filesystem: browse, preview, act (``/api/fa/fs/*``)."""

from __future__ import annotations

from fastapi.responses import FileResponse, JSONResponse

from api.common import (
    CreateBody, PathBody, PathsBody, PickBody, RenameBody, TransferBody, api_router, respond,
)
from files import fs_service, thumbnails
from files.security import is_secret_path

router = api_router("fs")


def _not_found(message: str) -> JSONResponse:
    return JSONResponse({"ok": False, "error": {"code": "ENOENT", "message": message}}, status_code=404)


@router.get("/fs/home")
def home():
    return respond(fs_service.home)


@router.get("/fs/quick-access")
def quick_access():
    return respond(fs_service.quick_access)


@router.get("/fs/drives")
def drives():
    return respond(fs_service.drives)


@router.get("/fs/list")
def list_dir(path: str, hidden: bool = False):
    return respond(lambda: fs_service.list_dir(path, show_hidden=hidden))


@router.get("/fs/info")
def info(path: str):
    return respond(lambda: fs_service.get_info(path))


@router.get("/fs/folder-size")
def folder_size(path: str):
    return respond(lambda: fs_service.folder_size(path))


@router.get("/fs/preview")
def preview(path: str):
    return respond(lambda: fs_service.preview(path))


@router.get("/fs/search")
def name_search(q: str, root: str, limit: int = 300):
    return respond(lambda: fs_service.name_search(q, root, limit=limit))


@router.post("/fs/create-folder")
def create_folder(body: CreateBody):
    return respond(lambda: fs_service.create_folder(body.parent, body.name))


@router.post("/fs/create-file")
def create_file(body: CreateBody):
    return respond(lambda: fs_service.create_file(body.parent, body.name, body.content))


@router.post("/fs/rename")
def rename(body: RenameBody):
    return respond(lambda: fs_service.rename(body.path, body.newName))


@router.post("/fs/copy")
def copy(body: TransferBody):
    return respond(lambda: fs_service.copy(body.sources, body.dest))


@router.post("/fs/move")
def move(body: TransferBody):
    return respond(lambda: fs_service.move(body.sources, body.dest))


@router.post("/fs/duplicate")
def duplicate(body: PathsBody):
    return respond(lambda: fs_service.duplicate(body.paths))


@router.post("/fs/trash")
def trash(body: PathsBody):
    return respond(lambda: fs_service.trash(body.paths))


@router.post("/fs/open")
def open_path(body: PathBody):
    return respond(lambda: fs_service.open_path(body.path))


@router.post("/fs/reveal")
def reveal(body: PathBody):
    return respond(lambda: fs_service.reveal(body.path))


@router.post("/fs/access")
def access(body: PathsBody):
    """Which folders the OS currently lets DeskMate read (macOS privacy prompts)."""
    return respond(lambda: fs_service.probe_access(body.paths))


@router.post("/fs/pick-folders")
def pick_folders(body: PickBody):
    """Open the native folder chooser; ``data`` is the chosen folders ([] if cancelled)."""
    return respond(lambda: fs_service.pick_folders(body.prompt, body.multiple))


@router.post("/fs/open-privacy-settings")
def open_privacy_settings():
    return respond(fs_service.open_privacy_settings)


@router.get("/fs/thumbnail")
def thumbnail(path: str, size: int = 256):
    try:
        thumb = thumbnails.thumbnail(path, size)
    except OSError:
        thumb = None
    if thumb is None:
        return _not_found("No thumbnail.")
    return FileResponse(thumb, media_type="image/png", headers={"Cache-Control": "max-age=86400"})


@router.get("/fs/raw")
def raw(path: str):
    """Stream a file's bytes for in-app preview (images, PDF, media). Never secrets."""
    from pathlib import Path

    p = Path(path)
    if not p.is_absolute() or not p.is_file() or is_secret_path(p):
        return _not_found("Not available.")
    return FileResponse(p)
