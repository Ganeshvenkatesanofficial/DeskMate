"""
services.meeting_intelligence.screen_capture
============================================
Backward compatibility alias module.
The core implementation is now organized under `screen_capture_service`.
"""

from .screen_capture_service import ScreenCapture

__all__ = ["ScreenCapture"]
