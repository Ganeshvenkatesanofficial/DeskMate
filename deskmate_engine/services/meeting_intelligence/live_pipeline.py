"""
services.meeting_intelligence.live_pipeline — 8-Stage Real-Time Meeting Event Pipeline
====================================================================================
Consumes frames from ScreenCapture and executes the full 8-stage detection architecture:
  1. Spatial Awareness & Safety Masking (SpatialAnalyzer)
  2. Change Detection & Frame Differencing (ChangeDetector)
  3. Visual Uniqueness Dedup (SSIM)
  4. Cursor Tracking & Click Detection (CursorDetector)
  5. Action-Centric ROI Extraction (ActionCentricROIExtractor)
  6. Interaction Detection (InteractionDetector)
  7. Heuristic & NVIDIA LocateAnything-3B GUI Grounding
  8. Temporal Tracking & Chronological Step Building (StepBuilder)
"""

from __future__ import annotations

import json
import logging
import threading
import time
import uuid
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Optional
import cv2
import numpy as np

from . import config as mi_config
from .modules.spatial_analyzer import SpatialAnalyzer
from .modules.change_detector import ChangeDetector, compute_ssim
from .modules.cursor_detector import CursorDetector
from .modules.interaction_detector import InteractionDetector
from .modules.roi_extractor import ActionCentricROIExtractor
from .modules.heuristic_classifier import HeuristicUIClassifier
from .modules.decision_gate import DecisionGate
from .modules.tracker import TemporalTracker
from .modules.action_inference import CursorInformedActionInference
from .modules.step_builder import StepBuilder
from .modules.locate_anything import LocateAnythingDetector
from .screen_capture_service import ScreenCapture
from .step_utils import check_deskmate_recording_frame


logger = logging.getLogger("deskmate.live_pipeline")

# How often an in-progress meeting is saved, so a crash or sleep keeps its data.
INTERIM_SAVE_SECONDS = 10.0


class PipelineState(str, Enum):
    """Execution states for LivePipeline."""
    IDLE = "idle"
    RECORDING = "recording"
    PAUSED = "paused"
    STOPPED = "stopped"


class LivePipeline:
    """
    Real-time meeting event detection pipeline.
    Runs the complete 8-stage computer vision workflow on screen frames.
    """

    STATE_IDLE = PipelineState.IDLE
    STATE_RECORDING = PipelineState.RECORDING
    STATE_PAUSED = PipelineState.PAUSED
    STATE_STOPPED = PipelineState.STOPPED

    def __init__(
        self,
        screen_capture: ScreenCapture,
        output_dir: str = "output/sessions",
        event_callback: Callable[[dict[str, Any]], None] | None = None,
        grounding_enabled: bool = True,
    ):
        self.screen_capture = screen_capture
        self.output_dir = output_dir
        self.event_callback = event_callback
        self.grounding_enabled = grounding_enabled

        self._state = self.STATE_IDLE
        self._session_id: str | None = None
        self._session_start: float | None = None
        self._last_disk_sync = 0.0
        # Serializes report writes so an interim save can't overwrite the final one.
        self._save_lock = threading.Lock()
        self._assets_dir: str | None = None
        self._process_thread: threading.Thread | None = None

        # Stats
        self._frames_processed = 0
        self._frames_skipped = 0
        self._grounding_calls = 0
        self._events_detected = 0

        # Visual dedup
        self._last_unique_frame_gray: np.ndarray | None = None

        # Multi-stage detection modules
        self._spatial_analyzer = SpatialAnalyzer()
        self._change_detector = ChangeDetector()
        self._cursor_detector = CursorDetector()
        self._interaction_detector = InteractionDetector()
        self._roi_extractor = ActionCentricROIExtractor()
        self._heuristic_classifier = HeuristicUIClassifier()
        self._decision_gate = DecisionGate()
        self._tracker = TemporalTracker()
        self._action_inference = CursorInformedActionInference()
        self._step_builder = StepBuilder()
        self._locate_anything = LocateAnythingDetector() if grounding_enabled else None
        self._has_initial_baseline = False
        self._last_milestone_time = 0.0
        self._pending_post_click_capture = False
        self._post_click_time = 0.0
        self._post_click_target = ""

        self.events: list[dict[str, Any]] = []

    @property
    def state(self) -> str:
        return self._state

    @property
    def stats(self) -> dict[str, Any]:
        uptime = round(time.time() - self._session_start, 1) if self._session_start else 0.0
        return {
            "state": self._state,
            "session_id": self._session_id,
            "uptime_seconds": uptime,
            "frames_processed": self._frames_processed,
            "frames_skipped": self._frames_skipped,
            "events_detected": self._events_detected,
            "grounding_calls": self._grounding_calls,
            "steps_count": self._step_builder.get_step_count() if self._step_builder else 0,
        }

    def start(self, session_id: str | None = None) -> str:
        """Start the screen capture and 8-stage consumer processing thread."""
        if self._state == self.STATE_RECORDING:
            logger.warning("LivePipeline is already running.")
            return self._session_id or ""

        self._session_id = session_id or datetime.now().strftime("%Y%m%d_%H%M%S")
        self._session_start = time.time()
        self._assets_dir = str(Path(self.output_dir) / self._session_id / "assets")
        Path(self._assets_dir).mkdir(parents=True, exist_ok=True)

        self.events = []
        self._frames_processed = 0
        self._frames_skipped = 0
        self._grounding_calls = 0
        self._events_detected = 0
        self._last_unique_frame_gray = None
        self._change_detector.reset()
        self._step_builder = StepBuilder()
        self._last_disk_sync = time.time()
        self._has_initial_baseline = False
        self._last_milestone_time = 0.0
        self._pending_post_click_capture = False
        self._post_click_time = 0.0
        self._post_click_target = ""

        # Immediate initial persistence to guarantee session exists on disk even if interrupted
        self._save_session_report([], status="recording")

        self.screen_capture.start()
        self._state = self.STATE_RECORDING
        self._process_thread = threading.Thread(target=self._processing_loop, daemon=True, name="LivePipelineThread")
        self._process_thread.start()

        logger.info(f"LivePipeline session started: {self._session_id}")
        return self._session_id

    def stop(self) -> dict[str, Any]:
        """Stop processing and compile the final session report."""
        if self._state == self.STATE_IDLE or self._state == self.STATE_STOPPED:
            return self.stats

        self._state = self.STATE_STOPPED
        self.screen_capture.stop()

        if self._process_thread and self._process_thread.is_alive():
            self._process_thread.join(timeout=3.0)

        # Fallback overview milestone if zero steps were captured during short/static session
        if self._step_builder and self._step_builder.get_step_count() == 0:
            last_res = self.screen_capture.get_frame(timeout=0.5)
            if last_res:
                _, ts, last_frame = last_res
                evt = self._create_event(
                    "screen_presentation",
                    "Meeting Overview",
                    None,
                    [0, 0, last_frame.shape[1], last_frame.shape[0]],
                    last_frame,
                    ts,
                    1.0,
                )
                self._record_event(evt)

        steps = self._step_builder.get_all_steps() if self._step_builder else []
        report = self._save_session_report(steps)

        self._state = self.STATE_IDLE
        logger.info(f"LivePipeline stopped. Generated {len(steps)} steps across {self._events_detected} events.")
        return report

    def pause(self) -> None:
        self._state = self.STATE_PAUSED
        self.screen_capture.pause()

    def resume(self) -> None:
        self._state = self.STATE_RECORDING
        self.screen_capture.resume()

    def _processing_loop(self) -> None:
        """Consumer thread processing incoming screen frames."""
        logger.info("LivePipeline consumer loop started.")

        while self._state in (self.STATE_RECORDING, self.STATE_PAUSED):
            if self._state == self.STATE_PAUSED:
                time.sleep(0.1)
                continue

            result = self.screen_capture.get_frame(timeout=1.0)
            if result is None:
                continue

            frame_idx, timestamp, frame = result
            try:
                self._process_frame(frame_idx, timestamp, frame)
            except Exception as e:
                logger.error(f"Error processing frame {frame_idx}: {e}")

        logger.info("LivePipeline consumer loop exited.")

    def _process_frame(self, frame_idx: int, timestamp: float, frame: np.ndarray) -> None:
        """Execute full 8-stage computer vision detection on a single frame."""
        # Settling grace period: skip the click on DeskMate's own 'Start Meeting' button
        if self._session_start and (time.time() - self._session_start < mi_config.STARTUP_GRACE_SECONDS):
            return

        # Skip any frame that shows DeskMate's own recording screen (red record circle + End Meeting pill)
        if check_deskmate_recording_frame(frame):
            self._frames_skipped += 1
            return

        # Stage 1: Spatial Awareness & Safety Mask
        self._spatial_analyzer.detect_sidebar(frame)
        safety_mask = self._spatial_analyzer.get_safety_mask(*frame.shape[:2])

        # Stage 4: Cursor Detection & Tracking
        cursor_pos, _ = self._cursor_detector.detect(frame, safety_mask)

        # Baseline Frame: Capture initial presentation frame once user is on real meeting content
        if not self._has_initial_baseline:
            self._has_initial_baseline = True
            self._last_milestone_time = timestamp
            self._frames_processed += 1
            _, roi_bbox = self._roi_extractor.extract_relevant_roi(frame, cursor_pos, None, safety_mask)
            event = self._create_event("screen_presentation", "Presentation Initial View", cursor_pos, roi_bbox, frame, timestamp, 1.0)
            if self._record_event(event):
                logger.info(f"Captured initial baseline meeting step at {timestamp:.1f}s")
            return

        # Check if we have a pending post-click transition capture (0.4s - 1.5s after user clicked)
        is_post_click_transition = False
        if self._pending_post_click_capture:
            elapsed = timestamp - self._post_click_time
            if 0.4 <= elapsed <= 1.5:
                is_post_click_transition = True
                self._pending_post_click_capture = False
            elif elapsed > 1.5:
                self._pending_post_click_capture = False

        # Stage 2: Change Detection & Early Candidate Filtering
        is_candidate, _, _, mask = self._change_detector.is_candidate_frame(frame)
        if mask is None and not is_post_click_transition:
            self._frames_skipped += 1
            return

        # Periodic checkpoint so long static views (one slide, a video call) still get screenshots
        is_periodic_checkpoint = timestamp - self._last_milestone_time >= mi_config.MILESTONE_INTERVAL_SECONDS

        # Stage 3: Visual Dedup (SSIM)
        if not is_periodic_checkpoint and not is_post_click_transition and not self._is_visually_unique(frame):
            self._frames_skipped += 1
            return

        self._frames_processed += 1

        # Stage 5: Action-Centric ROI Extraction
        roi_frame, roi_bbox = self._roi_extractor.extract_relevant_roi(
            frame, cursor_pos, mask, safety_mask
        )
        if roi_frame is None or roi_bbox is None:
            roi_frame = frame
            roi_bbox = [0, 0, frame.shape[1], frame.shape[0]]

        # Stage 6: Interaction Detection
        roi_mask = mask[roi_bbox[1]:roi_bbox[3], roi_bbox[0]:roi_bbox[2]] if mask is not None else None
        interactions = self._interaction_detector.detect_interactions(
            cursor_pos, is_candidate, timestamp, motion_patch=roi_mask
        )

        is_valid = bool(interactions or cursor_pos is not None)
        if not is_valid and not is_candidate and not is_periodic_checkpoint and not is_post_click_transition:
            return

        # Stage 7: Heuristic & LocateAnything-3B GUI Grounding
        h_label, h_conf = self._heuristic_classifier.classify(roi_frame)
        final_label = h_label
        final_score = h_conf

        if (
            self.grounding_enabled
            and self._locate_anything
            and is_valid
            and self._decision_gate.needs_grounding(h_label, h_conf)
        ):
            detections = self._locate_anything.detect(roi_frame)
            if detections:
                final_label = detections[0]["label"]
                final_score = detections[0]["score"]
                self._grounding_calls += 1

        # Stage 8: Temporal Tracking & Action Inference
        self._tracker.update([{"label": final_label, "score": final_score, "box": roi_bbox}], timestamp)
        action = self._action_inference.infer(final_label, interactions)

        if is_post_click_transition:
            # Resulting destination screen after user clicked
            action = "screen_presentation"
            if not final_label or final_label.lower() in ["unknown", "generic_view", "modal_window", "unclassified", "button"]:
                final_label = f"Result of {self._post_click_target}" if self._post_click_target else "Screen Transition"
            self._last_milestone_time = timestamp
        elif action in ["observed_interaction", "unclassified"] and is_valid:
            action = "ui_interaction"
            if "click" in interactions or "button" in str(final_label).lower():
                self._pending_post_click_capture = True
                self._post_click_time = timestamp
                self._post_click_target = final_label
        elif is_candidate or is_periodic_checkpoint:
            # Visual presentation transition / slide advance during meeting
            action = "screen_presentation"
            if not final_label or final_label.lower() in ["unknown", "generic_view", "modal_window", "unclassified"]:
                final_label = "Presentation Milestone" if is_candidate else "Presentation Checkpoint"
            self._last_milestone_time = timestamp

        # Create structured event and add to StepBuilder
        event = self._create_event(action, final_label, cursor_pos, roi_bbox, frame, timestamp, final_score)
        if self._record_event(event):
            # Periodically sync progress to disk so crash/sleep never loses meeting data
            now = time.time()
            if now - self._last_disk_sync >= INTERIM_SAVE_SECONDS:
                self._last_disk_sync = now
                interim_steps = self._step_builder.get_current_steps() if self._step_builder else []
                self._save_session_report(interim_steps, status="recording")

            if self.event_callback:
                try:
                    self.event_callback(event)
                except Exception as cb_err:
                    logger.error(f"Event callback error: {cb_err}")

    def _record_event(self, event: Optional[dict[str, Any]]) -> bool:
        """Add a created event to the current step. False if the event couldn't be created."""
        if not event:
            return False
        self._step_builder.add_action(event)
        self.events.append(event)
        self._events_detected += 1
        return True

    @staticmethod
    def _dedup_thumbnail(frame: np.ndarray) -> np.ndarray:
        return cv2.resize(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), mi_config.DEDUP_THUMBNAIL_SIZE)

    def _is_visually_unique(self, frame: np.ndarray) -> bool:
        """Check if frame differs from the last saved screenshot via SSIM."""
        if self._last_unique_frame_gray is None:
            return True

        f1 = self._last_unique_frame_gray
        f2 = self._dedup_thumbnail(frame)

        score = compute_ssim(f1, f2)

        # Visual difference threshold
        if score > mi_config.MIN_VISUAL_DIFF_SSIM:
            return False

        return True

    def _create_event(
        self,
        action: str,
        label: str,
        cursor_pos: tuple[int, int] | None,
        bbox: list[int] | None,
        frame: np.ndarray,
        timestamp_sec: float,
        confidence: float = 0.0,
    ) -> dict[str, Any] | None:
        """Save high-resolution screenshot and return structured event dictionary."""
        # Discard internal application noise or dock/switcher actions
        combined_label = f"{action} {label}".lower()
        internal_patterns = [
            "deskmate", "meeting scribe", "start meeting", "end meeting",
            "stop meeting", "recording dashboard", "dock", "app switcher",
            "mission control", "taskbar"
        ]
        if any(p in combined_label for p in internal_patterns):
            logger.debug(f"Filtered internal app/switch event: {combined_label}")
            return None

        event_id = str(uuid.uuid4())[:8]
        filename = f"event_{event_id}_{int(timestamp_sec)}.jpg"
        filepath = str(Path(self._assets_dir) / filename) if self._assets_dir else None

        try:
            if filepath:
                cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])[1].tofile(filepath)
                self._last_unique_frame_gray = self._dedup_thumbnail(frame)
        except Exception as e:
            logger.error(f"Failed to save step screenshot: {e}")
            filepath = None

        asset_rel = str(Path(self.output_dir) / self._session_id / "assets" / filename) if (filepath and self._session_id) else None
        m = int(timestamp_sec // 60)
        s = int(timestamp_sec % 60)

        return {
            "timestamp": f"{m:02d}:{s:02d}",
            "timestamp_raw": round(timestamp_sec, 2),
            "event": action,
            "target": label,
            "confidence": round(confidence, 3),
            "bbox": list(bbox) if bbox else [],
            "cursor": list(cursor_pos) if cursor_pos else [],
            "asset_path": asset_rel,
            "id": event_id,
        }

    def _save_session_report(self, steps: list[dict[str, Any]], status: str = "completed") -> dict[str, Any]:
        """Save the session report JSON. Interim ("recording") saves are skipped once stopped."""
        with self._save_lock:
            if status == "recording" and self._state == self.STATE_STOPPED:
                return {}
            return self._write_session_report(steps, status)

    def _write_session_report(self, steps: list[dict[str, Any]], status: str) -> dict[str, Any]:
        now = time.time()
        duration = round(now - self._session_start, 1) if self._session_start else 0.0
        report = {
            "session_id": self._session_id,
            "start_time": self._session_start,
            "end_time": now if status == "completed" else None,
            "duration_seconds": duration,
            "total_frames": self._frames_processed,
            "total_steps": len(steps),
            "steps": steps,
            "events": self.events,
            "status": status,
        }
        report_path = str(Path(self.output_dir) / f"session_{self._session_id}.json")
        try:
            with open(report_path, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=2, default=str)
        except Exception as e:
            logger.error(f"Failed to write session report: {e}")
        return report
