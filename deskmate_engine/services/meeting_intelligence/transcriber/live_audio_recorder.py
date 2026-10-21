"""
services.meeting_intelligence.transcriber.live_audio_recorder
=============================================================
Backward compatibility alias module.
The core implementation is now organized under `audio_service.live_audio_recorder`.
"""

from ..audio_service.live_audio_recorder import (
    LiveAudioRecorder,
    SAMPLE_RATE,
    CHANNELS,
)

__all__ = ["LiveAudioRecorder", "SAMPLE_RATE", "CHANNELS"]
