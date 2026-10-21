"""
services.meeting_intelligence.transcriber.audio_extractor
=========================================================
Backward compatibility alias module.
The core implementation is now organized under `audio_service.audio_extractor`.
"""

from ..audio_service.audio_extractor import (
    AudioExtractor,
    SAMPLE_RATE,
    CHANNELS,
)

__all__ = ["AudioExtractor", "SAMPLE_RATE", "CHANNELS"]
