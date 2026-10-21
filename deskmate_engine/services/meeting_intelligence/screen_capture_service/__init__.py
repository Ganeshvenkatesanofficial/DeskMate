"""
services.meeting_intelligence.screen_capture_service
====================================================
Dedicated high-performance screen capture service utilizing mss.
Exposes thread-safe multi-monitor grabber with < 1.5% CPU overhead.
"""

from .screen_capture import ScreenCapture

__all__ = ["ScreenCapture"]
