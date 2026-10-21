"""
services.meeting_intelligence.transcriber.voxtral_service
=========================================================
Backward compatibility alias module.
The core implementation is now organized under `audio_service.voxtral_service`.
"""

from ..audio_service.voxtral_service import (
    VoxtralSpeechEngine,
)

__all__ = ["VoxtralSpeechEngine"]
