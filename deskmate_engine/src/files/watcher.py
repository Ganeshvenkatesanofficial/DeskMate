"""
files.watcher — Live folder change notifications
================================================================
The explorer only needs to know when the folder *in view* changes, so
instead of a recursive OS watcher this polls a small, ref-counted set of
folders once a second (a cheap ``scandir`` signature) and publishes
``fs.changed`` events. No native dependency, identical on every OS.
"""

from __future__ import annotations

import hashlib
import os
import threading
from collections import Counter

from db import events

POLL_S = 1.0


class FolderWatcher:
    def __init__(self) -> None:
        self._refs: Counter[str] = Counter()
        self._sigs: dict[str, str] = {}
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None

    @staticmethod
    def _signature(path: str) -> str:
        h = hashlib.blake2b(digest_size=16)
        try:
            with os.scandir(path) as it:
                for de in sorted(it, key=lambda d: d.name):
                    try:
                        st = de.stat(follow_symlinks=False)
                        h.update(f"{de.name}|{st.st_mtime_ns}|{st.st_size}\n".encode())
                    except OSError:
                        h.update(f"{de.name}|?\n".encode())
        except OSError:
            return "missing"
        return h.hexdigest()

    def watch(self, path: str) -> None:
        with self._lock:
            self._refs[path] += 1
            if path not in self._sigs:
                self._sigs[path] = self._signature(path)
            if self._thread is None or not self._thread.is_alive():
                self._thread = threading.Thread(target=self._loop, name="fa-watcher", daemon=True)
                self._thread.start()

    def unwatch(self, path: str) -> None:
        with self._lock:
            self._refs[path] -= 1
            if self._refs[path] <= 0:
                del self._refs[path]
                self._sigs.pop(path, None)

    def touch(self, *paths: str) -> None:
        """Announce a change we caused ourselves (agent action) without waiting for the poll."""
        for p in {p for p in paths if p}:
            events.publish("fs.changed", path=p)

    def _loop(self) -> None:
        stop = threading.Event()
        while True:
            with self._lock:
                watched = list(self._refs)
            if not watched:
                return
            for path in watched:
                sig = self._signature(path)
                with self._lock:
                    old = self._sigs.get(path)
                    if path in self._refs:
                        self._sigs[path] = sig
                if old is not None and old != sig:
                    events.publish("fs.changed", path=path)
            stop.wait(POLL_S)


WATCHER = FolderWatcher()
