"""
services.meeting_intelligence.transcriber
=========================================
Backward compatibility alias package.
The core audio components are now organized under `audio_service`.
"""

from ..audio_service import (
    LiveAudioRecorder,
    VoxtralSpeechEngine,
    AudioExtractor,
    ChunkedTranscriber,
    SAMPLE_RATE,
    CHANNELS,
)

__all__ = [
    "LiveAudioRecorder",
    "VoxtralSpeechEngine",
    "AudioExtractor",
    "ChunkedTranscriber",
    "SAMPLE_RATE",
    "CHANNELS",
]
