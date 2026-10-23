"""
services.meeting_intelligence.screen_capture — Low-Overhead Screen Grabber
========================================================================
Uses mss for high-performance, non-blocking screen capture across macOS & Windows.
Runs in a dedicated thread consuming < 1.5% CPU at 2.0 target FPS.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any, Dict, Optional, Tuple
import numpy as np

try:
    import mss
    HAS_MSS = True
except ImportError:
    HAS_MSS = False

logger = logging.getLogger("deskmate.screen_capture")


class ScreenCapture:
    """
    Captures screen frames at a specified target FPS and exposes a thread-safe
    latest-frame buffer to the detection pipeline.
    """

    def __init__(
        self,
        monitor: int = 1,
        region: Optional[Dict[str, int]] = None,
        fps: float = 2.0,
    ):
        if not HAS_MSS:
            raise ImportError("mss is required for screen capture. Install with: pip install mss")

        self.monitor_idx = monitor
        self.region = region
        self.target_fps = fps
        self.frame_interval = 1.0 / max(0.5, fps)

        self._running = False
        self._paused = False
        self._thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()

        self._latest_frame: Optional[Tuple[int, float, np.ndarray]] = None
        self._frame_ready = threading.Event()

        self._frame_count = 0
        self._start_time: float = 0.0
        self._actual_fps: float = 0.0
        self._resolution: Tuple[int, int] = (0, 0)

    @property
    def stats(self) -> Dict[str, Any]:
        uptime = round(time.time() - self._start_time, 1) if self._start_time else 0.0
        return {
            "running": self._running,
            "paused": self._paused,
            "frame_count": self._frame_count,
            "actual_fps": round(self._actual_fps, 2),
            "target_fps": self.target_fps,
            "resolution": self._resolution,
            "uptime": uptime,
        }

    def start(self) -> None:
        """Start the background screen grabber daemon thread."""
        if self._running:
            logger.warning("ScreenCapture is already active.")
            return

        self._running = True
        self._paused = False
        self._frame_count = 0
        self._start_time = time.time()
        self._thread = threading.Thread(target=self._capture_loop, daemon=True, name="ScreenCaptureThread")
        self._thread.start()
        logger.info(f"ScreenCapture started at {self.target_fps} FPS (Monitor: {self.monitor_idx})")

    def stop(self) -> None:
        """Stop screen capture."""
        self._running = False
        self._frame_ready.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._thread = None
        logger.info(f"ScreenCapture stopped. Total frames captured: {self._frame_count}")

    def pause(self) -> None:
        self._paused = True

    def resume(self) -> None:
        self._paused = False

    def get_frame(self, timeout: float = 1.0) -> Optional[Tuple[int, float, np.ndarray]]:
        """Retrieve the latest frame (frame_idx, timestamp, frame_bgr)."""
        if not self._frame_ready.wait(timeout=timeout):
            return None

        with self._lock:
            self._frame_ready.clear()
            frame = self._latest_frame
            self._latest_frame = None
            return frame

    def _capture_loop(self) -> None:
        fps_timer = time.time()
        fps_frames = 0

        with mss.mss() as sct:
            if self.region:
                monitor_cfg = self.region
            else:
                monitors = sct.monitors
                mon_idx = min(self.monitor_idx, len(monitors) - 1)
                monitor_cfg = monitors[mon_idx]

            self._resolution = (monitor_cfg["width"], monitor_cfg["height"])

            while self._running:
                loop_start = time.time()

                if not self._paused:
                    try:
                        sct_img = sct.grab(monitor_cfg)
                        # BGRA -> BGR
                        frame_bgr = np.ascontiguousarray(np.array(sct_img)[:, :, :3])
                        timestamp = time.time() - self._start_time
                        self._frame_count += 1

                        with self._lock:
                            self._latest_frame = (self._frame_count, timestamp, frame_bgr)
                            self._frame_ready.set()

                        fps_frames += 1
                        now = time.time()
                        if now - fps_timer >= 2.0:
                            self._actual_fps = fps_frames / (now - fps_timer)
                            fps_frames = 0
                            fps_timer = now

                    except Exception as e:
                        logger.error(f"Screen capture frame error: {e}")

                elapsed = time.time() - loop_start
                sleep_time = max(0.001, self.frame_interval - elapsed)
                time.sleep(sleep_time)
