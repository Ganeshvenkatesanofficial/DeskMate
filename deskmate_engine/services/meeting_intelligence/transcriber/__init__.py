"""
services.meeting_intelligence.transcriber — Voxtral 4B Transcription Subsystem
==============================================================================
"""

from .voxtral_service import VoxtralSpeechEngine
from .audio_extractor import AudioExtractor
from .chunked_transcriber import ChunkedTranscriber
from .vad import VoiceActivityDetector

__all__ = [
    "VoxtralSpeechEngine",
    "AudioExtractor",
    "ChunkedTranscriber",
    "VoiceActivityDetector",
]
