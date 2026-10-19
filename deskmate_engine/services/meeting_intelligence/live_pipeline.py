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

import json
import logging
import os
import threading
import time
import uuid
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional, Tuple
import cv2
import numpy as np

from .modules.spatial_analyzer import SpatialAnalyzer
from .modules.change_detector import ChangeDetector
from .modules.cursor_detector import CursorDetector
from .modules.interaction_detector import InteractionDetector
from .modules.roi_extractor import ActionCentricROIExtractor
from .modules.heuristic_classifier import HeuristicUIClassifier
from .modules.decision_gate import DecisionGate
from .modules.tracker import TemporalTracker
from .modules.action_inference import CursorInformedActionInference
from .modules.step_builder import StepBuilder
from .modules.locate_anything import LocateAnythingDetector
from .screen_capture import ScreenCapture

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    ssim = None

logger = logging.getLogger("deskmate.live_pipeline")


class LivePipeline:
    """
    Real-time meeting event detection pipeline.
    Runs the complete 8-stage computer vision workflow on screen frames.
    """

    STATE_IDLE = "idle"
    STATE_RECORDING = "recording"
    STATE_RUNNING = "recording"
    STATE_PAUSED = "paused"
    STATE_STOPPED = "stopped"

    def __init__(
        self,
        screen_capture: ScreenCapture,
        output_dir: str = "output/sessions",
        event_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
        grounding_enabled: bool = True,
    ):
        self.screen_capture = screen_capture
        self.output_dir = output_dir
        self.event_callback = event_callback
        self.grounding_enabled = grounding_enabled

        self._state = self.STATE_IDLE
        self._session_id: Optional[str] = None
        self._session_start: Optional[float] = None
        self._assets_dir: Optional[str] = None
        self._process_thread: Optional[threading.Thread] = None

        # Stats
        self._frames_processed = 0
        self._frames_skipped = 0
        self._grounding_calls = 0
        self._events_detected = 0

        # Visual dedup
        self._last_unique_frame_gray: Optional[np.ndarray] = None

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

        self.events: List[Dict[str, Any]] = []

    @property
    def state(self) -> str:
        return self._state

    @property
    def session_id(self) -> Optional[str]:
        return self._session_id

    @property
    def stats(self) -> Dict[str, Any]:
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

    def start(self, session_id: Optional[str] = None) -> str:
        """Start the screen capture and 8-stage consumer processing thread."""
        if self._state == self.STATE_RECORDING:
            logger.warning("LivePipeline is already running.")
            return self._session_id or ""

        self._session_id = session_id or datetime.now().strftime("%Y%m%d_%H%M%S")
        self._session_start = time.time()
        self._assets_dir = os.path.join(self.output_dir, self._session_id, "assets")
        os.makedirs(self._assets_dir, exist_ok=True)

        self.events = []
        self._frames_processed = 0
        self._frames_skipped = 0
        self._grounding_calls = 0
        self._events_detected = 0
        self._last_unique_frame_gray = None
        self._change_detector.reset()
        self._step_builder = StepBuilder()

        self.screen_capture.start()
        self._state = self.STATE_RECORDING
        self._process_thread = threading.Thread(target=self._processing_loop, daemon=True, name="LivePipelineThread")
        self._process_thread.start()

        logger.info(f"LivePipeline session started: {self._session_id}")
        return self._session_id

    def stop(self) -> Dict[str, Any]:
        """Stop processing and compile the final session report."""
        if self._state == self.STATE_IDLE or self._state == self.STATE_STOPPED:
            return self.stats

        self._state = self.STATE_STOPPED
        self.screen_capture.stop()

        if self._process_thread and self._process_thread.is_alive():
            self._process_thread.join(timeout=3.0)

        steps = self._step_builder.get_all_steps() if self._step_builder else []
        report = self._save_session_report(steps)

        self._state = self.STATE_IDLE
        logger.info(f"LivePipeline stopped. Generated {len(steps)} steps across {self._events_detected} events.")
        return report

    def pause(self) -> None:
        self._state = self.STATE_PAUSED
        self.screen_capture.pause()

    def resume(self) -> None:
        self._state = self.STATE_RUNNING
        self.screen_capture.resume()

    def _processing_loop(self) -> None:
        """Consumer thread processing incoming screen frames."""
        logger.info("LivePipeline consumer loop started.")

        while self._state in (self.STATE_RUNNING, self.STATE_PAUSED):
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
        # Initial settling grace period: ignore first 2.0s to avoid capturing click on 'Start Meeting' in DeskMate
        if self._session_start and (time.time() - self._session_start < 2.0):
            return

        # Stage 1: Spatial Awareness & Safety Mask
        self._spatial_analyzer.detect_sidebar(frame)
        safety_mask = self._spatial_analyzer.get_safety_mask(*frame.shape[:2])

        # Stage 2: Change Detection & Early Candidate Filtering
        is_candidate, _, _, mask = self._change_detector.is_candidate_frame(frame)
        if mask is None:
            self._frames_skipped += 1
            return

        # Stage 3: Visual Dedup (SSIM)
        if not self._is_visually_unique(frame):
            self._frames_skipped += 1
            return

        self._frames_processed += 1

        # Stage 4: Cursor Detection & Tracking
        cursor_pos, _ = self._cursor_detector.detect(frame, safety_mask)

        # Stage 5: Action-Centric ROI Extraction
        roi_frame, roi_bbox = self._roi_extractor.extract_relevant_roi(
            frame, cursor_pos, mask, safety_mask
        )
        if roi_frame is None or roi_bbox is None:
            return

        # Stage 6: Interaction Detection
        roi_mask = mask[roi_bbox[1]:roi_bbox[3], roi_bbox[0]:roi_bbox[2]]
        interactions = self._interaction_detector.detect_interactions(
            cursor_pos, is_candidate, timestamp, motion_patch=roi_mask
        )

        is_valid = bool(interactions or cursor_pos is not None)
        if not is_valid and not is_candidate:
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

        if action in ["observed_interaction", "unclassified"] and is_valid:
            action = "ui_interaction"

        # Create structured event and add to StepBuilder
        event = self._create_event(action, final_label, cursor_pos, roi_bbox, frame, timestamp)
        if event:
            self._step_builder.add_action(event)
            self.events.append(event)
            self._events_detected += 1

            if self.event_callback:
                try:
                    self.event_callback(event)
                except Exception as cb_err:
                    logger.error(f"Event callback error: {cb_err}")

    def _is_visually_unique(self, frame: np.ndarray) -> bool:
        """Check if frame differs from the last unique frame via SSIM."""
        if self._last_unique_frame_gray is None:
            self._last_unique_frame_gray = cv2.resize(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), (320, 180))
            return True

        f1 = self._last_unique_frame_gray
        f2 = cv2.resize(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), (320, 180))

        if ssim:
            score = ssim(f1, f2)
        else:
            score = 1.0 - (np.sum((f1.astype("float") - f2.astype("float")) ** 2) / float(f1.shape[0] * f1.shape[1] * 255))

        # Visual difference threshold
        if score > 0.985:
            return False

        self._last_unique_frame_gray = f2
        return True

    def _create_event(
        self,
        action: str,
        label: str,
        cursor_pos: Optional[Tuple[int, int]],
        bbox: Optional[List[int]],
        frame: np.ndarray,
        timestamp_sec: float,
    ) -> Optional[Dict[str, Any]]:
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
        filepath = os.path.join(self._assets_dir, filename)

        try:
            cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])[1].tofile(filepath)
        except Exception as e:
            logger.error(f"Failed to save step screenshot: {e}")
            filepath = None

        asset_rel = os.path.join(self.output_dir, self._session_id, "assets", filename) if filepath else None
        m = int(timestamp_sec // 60)
        s = int(timestamp_sec % 60)

        return {
            "timestamp": f"{m:02d}:{s:02d}",
            "timestamp_raw": round(timestamp_sec, 2),
            "event": action,
            "target": label,
            "confidence": 0.90,
            "bbox": list(bbox) if bbox else [],
            "cursor": list(cursor_pos) if cursor_pos else [],
            "asset_path": asset_rel,
            "id": event_id,
        }

    def _save_session_report(self, steps: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Save complete session report JSON to disk."""
        report = {
            "session_id": self._session_id,
            "start_time": self._session_start,
            "end_time": time.time(),
            "duration_seconds": round(time.time() - self._session_start, 1) if self._session_start else 0.0,
            "total_frames": self._frames_processed,
            "total_steps": len(steps),
            "steps": steps,
            "events": self.events,
        }
        report_path = os.path.join(self.output_dir, f"session_{self._session_id}.json")
        try:
            with open(report_path, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=2, default=str)
        except Exception as e:
            logger.error(f"Failed to write session report: {e}")
        return report
