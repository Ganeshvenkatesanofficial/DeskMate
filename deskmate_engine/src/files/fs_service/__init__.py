"""
files.fs_service — Public re-export surface
============================================
All callers import from ``files.fs_service`` as before — this package's
``__init__`` re-exports everything so no caller code needs to change.

Sub-modules:
  _base    — shared types: FsError, to_fs_error, entry_for, assert_valid_*
  browser  — read-only: list_dir, home, quick_access, drives, name_search …
  actions  — mutations: create, rename, copy, move, trash, open, pick_folders
  preview  — content reads: text preview, binary detection, PDF first page
"""

from __future__ import annotations

from files.fs_service._base import (
    FsError,
    assert_valid_name,
    assert_valid_path,
    entry_for,
    file_kind,
    to_fs_error,
    unique_destination,
)
from files.fs_service.browser import (
    drives,
    folder_size,
    get_info,
    home,
    is_glob,
    list_dir,
    name_match_tier,
    name_search,
    probe_access,
    quick_access,
)
from files.fs_service.actions import (
    copy,
    create_file,
    create_folder,
    duplicate,
    move,
    open_path,
    open_privacy_settings,
    pick_folders,
    rename,
    reveal,
    trash,
)
from files.fs_service.preview import preview

__all__ = [
    # _base
    "FsError", "to_fs_error", "assert_valid_path", "assert_valid_name",
    "entry_for", "file_kind", "unique_destination",
    # browser
    "home", "list_dir", "get_info", "quick_access", "drives", "folder_size",
    "name_search", "name_match_tier", "is_glob", "probe_access",
    # actions
    "create_folder", "create_file", "rename", "copy", "move", "duplicate",
    "trash", "open_path", "reveal", "open_privacy_settings", "pick_folders",
    # preview
    "preview",
]
