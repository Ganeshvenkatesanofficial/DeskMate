"""
services.meeting_intelligence.native_screen_ocr
================================================
Cross-Platform Native On-Device Screen OCR & Visual Intelligence Engine.
- macOS: Built-in Apple Vision framework (VNRecognizeTextRequest)
- Windows: Built-in Windows Runtime OCR (Windows.Media.Ocr.OcrEngine via PowerShell)
- Universal fallback: rapidocr-onnxruntime / pytesseract if installed

Features:
  1. Fast, offline, zero-cloud on-screen text extraction.
  2. Automatic video advertisement and commercial banner detection/filtering.
  3. Semantic cross-referencing between visual screen content and Voxtral audio.
  4. Dynamic extraction of meaningful screen titles and action descriptions.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
import re
import subprocess
import sys
from functools import lru_cache
from typing import Any, Optional

logger = logging.getLogger("deskmate.native_screen_ocr")

BIN_DIR = Path(__file__).resolve().parent.parent.parent / "bin"
SWIFT_BIN = BIN_DIR / "native_screen_ocr"

# Common keywords indicating video ads, sponsored promos, and commercials
AD_KEYWORDS = [
    "sponsored",
    "ad · 1 of",
    "ad 1 of",
    "ad 2 of",
    "skip ad",
    "skip ads",
    "skip in",
    "advertisement",
    "visit advertiser",
    "free credit",
    "claim credit",
    "promotional offer",
]

# Stopwords for audio-visual cross-referencing
STOPWORDS = {
    "the", "and", "or", "to", "in", "a", "an", "is", "it", "this", "that",
    "for", "on", "with", "as", "at", "by", "from", "up", "about", "into",
    "over", "after", "so", "we", "i", "you", "they", "he", "she", "all",
    "first", "alright", "just", "see", "demo", "action", "here", "can",
    "put", "use", "click", "next", "group", "moment", "simply",
}


@lru_cache(maxsize=1024)
def recognize_text(image_path: str) -> list[str]:
    """Extract recognized text lines from an image using the native OS OCR engine."""
    path = Path(image_path)
    if not path.is_file():
        return []

    # 1. macOS: Use pre-compiled Swift binary if available
    if os_is_macos():
        bin_to_use = SWIFT_BIN if SWIFT_BIN.is_file() else None
        if bin_to_use:
            try:
                res = subprocess.run(
                    [str(bin_to_use), str(path.resolve())],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if res.returncode == 0 and res.stdout.strip():
                    data = json.loads(res.stdout.strip())
                    if isinstance(data, list):
                        return [str(line).strip() for line in data if str(line).strip()]
            except Exception as e:
                logger.debug(f"Pre-compiled Swift OCR failed: {e}")

    # 2. Windows: Native Windows 10/11 OCR using built-in Windows.Media.Ocr
    if sys.platform == "win32":
        return _recognize_windows(path)

    # 3. macOS Fallback: Inline Swift script using Apple Vision framework
    if os_is_macos():
        swift_script = f"""
import Foundation
import Vision
import AppKit

let path = "{path.resolve()}"
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {{
    print("[]")
    exit(0)
}}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])

let recognized = request.results?.compactMap {{ $0.topCandidates(1).first?.string }} ?? []
if let data = try? JSONSerialization.data(withJSONObject: recognized),
   let json = String(data: data, encoding: .utf8) {{
    print(json)
}} else {{
    print("[]")
}}
"""
        try:
            res = subprocess.run(
                ["swift", "-e", swift_script],
                capture_output=True,
                text=True,
                timeout=8,
            )
            if res.returncode == 0 and res.stdout.strip():
                data = json.loads(res.stdout.strip())
                if isinstance(data, list):
                    return [str(line).strip() for line in data if str(line).strip()]
        except Exception as e:
            logger.debug(f"Inline Swift Apple Vision OCR failed: {e}")

    # 4. Universal cross-platform fallback (rapidocr / pytesseract)
    return _recognize_fallback(path)


def _recognize_windows(path: Path) -> list[str]:
    """Native Windows 10/11 offline OCR using built-in Windows.Media.Ocr via PowerShell (Zero pip dependencies)."""
    clean_path = str(path.resolve()).replace("'", "''")
    ps_script = f"""
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null

$file = [System.IO.Path]::GetFullPath('{clean_path}')
$asyncOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync($file)
$storageFile = $asyncOp.GetResults()
$streamOp = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)
$stream = $streamOp.GetResults()
$decoderOp = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
$decoder = $decoderOp.GetResults()
$bitmapOp = $decoder.GetSoftwareBitmapAsync()
$bitmap = $bitmapOp.GetResults()
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$ocrOp = $engine.RecognizeAsync($bitmap)
$result = $ocrOp.GetResults()

$lines = @()
foreach ($line in $result.Lines) {{
    $lines += $line.Text
}}
ConvertTo-Json -Compress $lines
"""
    try:
        res = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps_script],
            capture_output=True,
            text=True,
            timeout=8,
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            if isinstance(data, list):
                return [str(l).strip() for l in data if str(l).strip()]
            elif isinstance(data, str):
                return [data.strip()]
    except Exception as e:
        logger.debug(f"Windows native OCR failed: {e}")

    return _recognize_fallback(path)


def _recognize_fallback(path: Path) -> list[str]:
    """Universal cross-platform fallback using rapidocr-onnxruntime or pytesseract if installed."""
    try:
        from rapidocr_onnxruntime import RapidOCR
        engine = RapidOCR()
        result, _ = engine(str(path))
        if result:
            return [line[1] for line in result if line and len(line) > 1]
    except Exception:
        pass

    try:
        import pytesseract
        from PIL import Image
        text = pytesseract.image_to_string(Image.open(path))
        if text:
            return [l.strip() for l in text.splitlines() if l.strip()]
    except Exception:
        pass

    return []


def is_advertisement_or_commercial(lines: list[str]) -> tuple[bool, str]:
    """Check if the recognized screen text represents an ad, sponsored promo, or commercial.
    Returns (True, reason) or (False, '').
    """
    if not lines:
        return False, ""

    combined = " ".join(lines).lower()

    # Check for direct ad markers
    for kw in AD_KEYWORDS:
        if kw in combined:
            return True, f"Sponsored Advertisement / Commercial ('{kw}')"

    # Check for YouTube player ad timestamps (e.g. 0:03 / 0:15) + external domain banner
    has_countdown = bool(re.search(r"\b\d+:\d+\s*/\s*\d+:\d+\b", combined))
    has_commercial_domain = any(d in combined for d in [".com/ad", "cloud.google.com", "doubleclick", "adservice"])
    if has_countdown and has_commercial_domain:
        return True, "Video Player Commercial Banner"

    return False, ""


def cross_reference_image_and_audio(lines: list[str], transcript_text: str) -> float:
    """Compute semantic overlap score between screen OCR text and spoken transcript text.
    Returns a float score in [0.0, 1.0].
    """
    if not lines or not transcript_text:
        return 0.0

    ocr_words = set()
    for line in lines:
        for w in re.findall(r"[a-zA-Z0-9_\-]+", line.lower()):
            if len(w) > 2 and w not in STOPWORDS:
                ocr_words.add(w)

    transcript_words = set()
    for w in re.findall(r"[a-zA-Z0-9_\-]+", transcript_text.lower()):
        if len(w) > 2 and w not in STOPWORDS:
            transcript_words.add(w)

    if not ocr_words or not transcript_words:
        return 0.0

    overlap = ocr_words.intersection(transcript_words)
    score = len(overlap) / min(len(ocr_words), len(transcript_words))
    return min(1.0, score)


def extract_screen_title_and_context(lines: list[str], default_title: str = "Screen Interaction") -> dict[str, str]:
    """Synthesize meaningful title and UI interaction context directly from screen OCR text."""
    if not lines:
        return {
            "title": default_title,
            "description": "Screen content shown during the meeting.",
        }

    clean = [l.strip() for l in lines if len(l.strip()) > 1 and not re.match(r"^[\W_]+$", l.strip())]

    header = ""
    for l in clean[:6]:
        if any(h in l.lower() for h in ["create", "specify", "details", "console", "dashboard", "overview", "settings", "users", "iam", "aws", "configure"]):
            header = l
            break

    if not header and clean:
        header = clean[0]

    actions_found = []
    for l in clean:
        low = l.lower()
        if low in ["next", "cancel", "submit", "save", "create user", "sign in", "review and create", "set permissions"]:
            actions_found.append(f"'{l}'")

    action_text = f"Action elements visible: {', '.join(actions_found[:3])}." if actions_found else ""
    desc = f"Displaying {header}. {action_text}".strip()

    return {
        "title": header if len(header) < 60 else header[:57] + "...",
        "description": desc,
    }


def os_is_macos() -> bool:
    return sys.platform == "darwin"
