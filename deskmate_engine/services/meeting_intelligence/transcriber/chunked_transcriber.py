"""
services.meeting_intelligence.transcriber.chunked_transcriber
=============================================================
Backward compatibility alias module.
The core implementation is now organized under `audio_service.chunked_transcriber`.
"""

from ..audio_service.chunked_transcriber import (
    ChunkedTranscriber,
    AudioChunk,
    CHUNK_THRESHOLD_SECONDS,
    CHUNK_SIZE_SECONDS,
    OVERLAP_SECONDS,
)

__all__ = ["ChunkedTranscriber", "AudioChunk", "CHUNK_THRESHOLD_SECONDS", "CHUNK_SIZE_SECONDS", "OVERLAP_SECONDS"]
