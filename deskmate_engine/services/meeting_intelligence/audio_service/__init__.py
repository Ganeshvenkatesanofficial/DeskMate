"""
services.meeting_intelligence.audio_service
===========================================
Dedicated Audio Capture & Speech Intelligence Service.
Includes dual-stream audio capture (system loopback for speakers/bluetooth/jack
plus microphone), audio normalization, chunked processing, and Voxtral transcription.
"""

from .live_audio_recorder import LiveAudioRecorder, SAMPLE_RATE, CHANNELS
from .audio_extractor import AudioExtractor
from .chunked_transcriber import ChunkedTranscriber
from .voxtral_service import VoxtralSpeechEngine

__all__ = [
    "LiveAudioRecorder",
    "SAMPLE_RATE",
    "CHANNELS",
    "AudioExtractor",
    "ChunkedTranscriber",
    "VoxtralSpeechEngine",
]
