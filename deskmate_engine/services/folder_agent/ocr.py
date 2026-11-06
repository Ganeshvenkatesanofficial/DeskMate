"""
services.folder_agent.ocr — Zero-download native OCR for pictures
=================================================================
Makes screenshots, scans and photos of documents searchable without a vision
model, using the OS's own text recogniser:

* macOS   — Apple Vision through the bundled ``bin/native_screen_ocr`` helper;
* Windows — Windows.Media.Ocr through PowerShell.

Elsewhere (or if the OS engine fails) pictures are indexed by name only.
"""

from __future__ import annotations

import json
import logging
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

logger = logging.getLogger("deskmate.folder_agent.ocr")

# Packaged builds unpack bundled binaries under sys._MEIPASS; dev runs use the repo's bin/.
_BIN_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2])) / "bin"
_MAC_HELPER = _BIN_DIR / "native_screen_ocr"
_TIMEOUT_S = 8


def recognize_text(image_path: str | Path) -> list[str]:
    """Text lines found in the picture, best effort ([] when nothing is readable)."""
    path = Path(image_path)
    if not path.is_file():
        return []
    st = path.stat()
    return list(_recognize(str(path.resolve()), st.st_mtime_ns, st.st_size))


@lru_cache(maxsize=512)
def _recognize(path: str, _mtime_ns: int, _size: int) -> tuple[str, ...]:
    if sys.platform == "darwin":
        return tuple(_macos(path))
    if sys.platform == "win32":
        return tuple(_windows(path))
    return ()


def _lines(stdout: str) -> list[str]:
    data = json.loads(stdout.strip() or "[]")
    if isinstance(data, str):
        data = [data]
    return [str(line).strip() for line in data if str(line).strip()] if isinstance(data, list) else []


def _macos(path: str) -> list[str]:
    if not _MAC_HELPER.is_file():
        return []
    try:
        res = subprocess.run([str(_MAC_HELPER), path], capture_output=True, text=True, timeout=_TIMEOUT_S)
        return _lines(res.stdout) if res.returncode == 0 else []
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        logger.debug(f"[OCR] Vision helper failed for {path}: {exc}")
        return []


_WINDOWS_SCRIPT = r"""
param([string]$Path)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$await = [WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await($op, $type) { $t = $await.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(); $t.Result }
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
ConvertTo-Json -Compress @($result.Lines | ForEach-Object { $_.Text })
"""


def _windows(path: str) -> list[str]:
    try:
        # The path is passed as a parameter, never spliced into the script.
        res = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command",
             f"& {{{_WINDOWS_SCRIPT}}} -Path $args[0]", path],
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_S,
        )
        return _lines(res.stdout) if res.returncode == 0 else []
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        logger.debug(f"[OCR] Windows OCR failed for {path}: {exc}")
        return []
