"""
services.meeting_intelligence.step_utils — Shared helpers for recorded meeting steps
====================================================================================
Used by the summarizer and the PDF generator so both make the same decisions about
screenshots, DeskMate's own UI, step timing, spoken quotes and speaker labels.
"""

from __future__ import annotations

import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Optional

import cv2
import numpy as np

from services.meeting_intelligence import config

# Raw step text that means the capture shows DeskMate itself or a window switch, not meeting content.
HOST_UI_KEYWORDS = (
    "deskmate", "meeting scribe", "start meeting", "end meeting", "stop meeting",
    "recording dashboard", "telemetry", "modal_window", "modal", "runner", "flutter",
    "electron", "save to drive", "download pdf", "email pdf", "email meeting summary",
    "sync to deskmate", "app switcher", "mission control",
    "window switch", "switching window",
    "recording in progress",
)

# Step summaries that carry no information about what happened on screen.
GENERIC_STEP_SUMMARIES = ("screen presentation", "screen interaction", "unclassified", "ui interaction")

# Seconds around a step within which a transcript segment counts as spoken "at that moment".
QUOTE_WINDOW_SECONDS = 15.0
MAX_QUOTES_PER_STEP = 3

_SPEAKER_TAG = re.compile(r"\bSPEAKER_0*(\d+)\b", re.IGNORECASE)
_STEP_PREFIX = re.compile(r"^Step\s+\d+:\s*", re.IGNORECASE)
_GENERIC_TARGETS = {
    "", "button", "icon button", "unclassified", "interactive region", "menu bar", "menu item",
    "scroll bar", "text field", "checkbox", "link", "image", "element", "control", "widget",
}


def humanize_speaker_tags(text: str) -> str:
    """Replace machine diarization tags (SPEAKER_00) with 1-based labels (Speaker 1)."""
    return _SPEAKER_TAG.sub(lambda m: f"Speaker {int(m.group(1)) + 1}", text or "")


def step_number(step_id: Any) -> str:
    """'step_12', 12 or '12' -> '12' (the id itself when it has no digits)."""
    m = re.search(r"\d+", str(step_id))
    return m.group(0) if m else str(step_id)


def find_step(steps: list[dict[str, Any]], step_id: Any) -> Optional[dict[str, Any]]:
    num = step_number(step_id)
    return next((s for s in steps if step_number(s.get("step_id")) == num), None)


def step_seconds(step: dict[str, Any]) -> Optional[float]:
    """Seconds from meeting start at which the step began."""
    for action in step.get("actions") or []:
        if isinstance(action, dict) and action.get("timestamp_raw") is not None:
            try:
                return float(action["timestamp_raw"])
            except (TypeError, ValueError):
                break
    parts = str(step.get("timestamp") or "").split(":")
    if len(parts) == 2 and all(p.isdigit() for p in parts):
        return int(parts[0]) * 60.0 + int(parts[1])
    return None


def order_step_ids(step_ids: list[Any], steps: list[dict[str, Any]]) -> list[str]:
    """Drop repeated ids ('step_3' and '3' are the same step) and sort chronologically."""
    seconds = {step_number(s.get("step_id")): step_seconds(s) for s in steps}
    unique: dict[str, str] = {}
    for sid in step_ids:
        unique.setdefault(step_number(sid), str(sid))

    def sort_key(num: str) -> tuple[float, int]:
        secs = seconds.get(num)
        order = int(num) if num.isdigit() else 10**9
        return (secs if secs is not None else float(order), order)

    return [unique[num] for num in sorted(unique, key=sort_key)]


def resolve_screenshot_path(asset_rel_path: str, session_id: Optional[str] = None) -> Optional[str]:
    """Find a step screenshot across the dev workspace and the per-OS DeskMate data folders."""
    if not asset_rel_path:
        return None

    p = Path(asset_rel_path)
    if p.is_absolute() and p.exists():
        return str(p)

    candidates = [
        Path(config.OUTPUT_DIR) / asset_rel_path,
        Path(config.OUTPUT_DIR) / "live_sessions" / asset_rel_path,
        Path(asset_rel_path),
        Path.cwd() / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / "sessions" / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / "output" / "sessions" / asset_rel_path,
        Path.home() / "AppData" / "Roaming" / "DeskMate" / asset_rel_path,
        Path.home() / "AppData" / "Roaming" / "DeskMate" / "sessions" / asset_rel_path,
        Path.home() / "AppData" / "Roaming" / "DeskMate" / "output" / "sessions" / asset_rel_path,
    ]

    for prefix in ["output/sessions/", "sessions/", "live_sessions/", "output/"]:
        if asset_rel_path.startswith(prefix):
            stripped = asset_rel_path[len(prefix):]
            candidates.append(Path.home() / "Library" / "Application Support" / "DeskMate" / "output" / "sessions" / stripped)
            candidates.append(Path.home() / "Library" / "Application Support" / "DeskMate" / "sessions" / stripped)
            candidates.append(Path(config.OUTPUT_DIR) / stripped)
            candidates.append(Path("output/sessions") / stripped)

    filename = Path(asset_rel_path).name
    if session_id:
        clean_sid = str(session_id).strip()
        candidates.append(Path.home() / "Library" / "Application Support" / "DeskMate" / "output" / "sessions" / clean_sid / "assets" / filename)
        candidates.append(Path.home() / "Library" / "Application Support" / "DeskMate" / "sessions" / clean_sid / "assets" / filename)
        candidates.append(Path(config.OUTPUT_DIR) / clean_sid / "assets" / filename)
        candidates.append(Path("output/sessions") / clean_sid / "assets" / filename)

    for cand in candidates:
        try:
            if cand.exists() and cand.is_file():
                return str(cand.resolve())
        except Exception:
            continue
    return None


def step_screenshot_path(step: dict[str, Any]) -> Optional[str]:
    """Absolute path of the step's screenshot, or None."""
    rel = step.get("screenshot_path") or next(
        (a.get("asset_path") for a in step.get("actions") or [] if isinstance(a, dict) and a.get("asset_path")),
        "",
    )
    return resolve_screenshot_path(rel)


def check_deskmate_recording_frame(img: np.ndarray | None) -> bool:
    """True when the BGR image frame shows DeskMate's recording screen: a red record circle with
    the red 'End Meeting' pill below it. A red slide, banner or logo alone does not match."""
    if img is None or not isinstance(img, np.ndarray) or img.size == 0:
        return False

    blue, green, red = cv2.split(img)
    mask = ((red > 170) & (green < 80) & (blue < 80)).astype(np.uint8) * 255
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    min_height = min(img.shape[:2]) * 0.02
    circles, pills = [], []
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        if h < min_height:
            continue
        aspect = w / h
        fill = cv2.contourArea(contour) / (w * h)
        if 0.8 <= aspect <= 1.25 and 0.65 <= fill <= 0.88:
            circles.append((x + w / 2, y + h / 2, w))
        elif aspect >= 3 and fill >= 0.75:
            pills.append((x + w / 2, y + h / 2))

    return any(
        py > cy and abs(px - cx) < diameter
        for cx, cy, diameter in circles
        for px, py in pills
    )


@lru_cache(maxsize=512)
def shows_deskmate_recording_screen(image_path: Optional[str]) -> bool:
    """True when the screenshot shows DeskMate's recording screen: a red record circle with
    the red 'End Meeting' pill below it. A red slide, banner or logo alone does not match."""
    if not image_path:
        return False
    img = cv2.imread(image_path)
    return check_deskmate_recording_frame(img)


def is_host_ui_step(step: dict[str, Any]) -> bool:
    """True when the step captured DeskMate's own window or a window switch."""
    if not isinstance(step, dict):
        return False
    combined = " ".join(
        [str(step.get("summary") or "")]
        + [
            str(a.get("target") or a.get("description") or a.get("event") or "")
            for a in step.get("actions") or []
            if isinstance(a, dict)
        ]
    ).lower()
    if any(kw in combined for kw in HOST_UI_KEYWORDS):
        return True
    try:
        return shows_deskmate_recording_screen(step_screenshot_path(step))
    except Exception:
        return False


def spoken_quotes_near(transcript_data: Optional[dict[str, Any]], step: dict[str, Any]) -> str:
    """Transcript lines spoken around the step's time, as 'Speaker 1: "..."', or ''."""
    segments = (transcript_data or {}).get("segments") or []
    target = step_seconds(step)
    if target is None or not segments:
        return ""

    def near(seg: dict[str, Any]) -> bool:
        start = float(seg.get("start") or 0.0)
        end = float(seg.get("end") or start)
        return start - QUOTE_WINDOW_SECONDS <= target <= end + QUOTE_WINDOW_SECONDS

    matched = sorted((s for s in segments if isinstance(s, dict) and near(s)), key=lambda s: float(s.get("start") or 0.0))
    quotes = [
        f'{humanize_speaker_tags(str(s.get("speaker") or "Speaker 1"))}: "{str(s.get("text") or "").strip()}"'
        for s in matched[:MAX_QUOTES_PER_STEP]
        if str(s.get("text") or "").strip()
    ]
    return " ".join(quotes)


def readable_step_title(summary: str) -> str:
    """'Step 4: Click on Deploy' -> 'Click on Deploy'; generic summaries -> 'Screen Interaction'."""
    clean = _STEP_PREFIX.sub("", summary or "").strip()
    if not clean or any(g in clean.lower() for g in ("unclassified", "ui_interaction", "observed_interaction")):
        return "Screen Interaction"
    return clean


def fallback_step_description(step: dict[str, Any]) -> str:
    """Describe a step from its recorded actions when the AI gave no description."""
    parts: list[str] = []
    seen: set[str] = set()
    for action in (step.get("actions") or [])[:8]:
        if not isinstance(action, dict):
            continue
        target = str(action.get("target") or action.get("description") or "").strip()
        if target.lower() in _GENERIC_TARGETS or target.lower() in seen:
            continue
        seen.add(target.lower())
        event = str(action.get("event") or action.get("type") or "").lower()
        if event in ("type", "input", "text_input"):
            parts.append(f"Typed in: {target}")
        elif event == "scroll":
            parts.append(f"Scrolled: {target}")
        else:
            parts.append(f"Interacted with: {target}")
    if parts:
        return "; ".join(parts)

    title = readable_step_title(str(step.get("summary") or ""))
    if title.lower() not in GENERIC_STEP_SUMMARIES:
        return f"Operation performed on screen: {title}"
    return "Screen content shown during the meeting."
