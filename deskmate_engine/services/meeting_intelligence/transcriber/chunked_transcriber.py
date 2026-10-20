"""
transcriber.chunked_transcriber — Long Audio Chunking & Voxtral Stitching
========================================================================
Handles extended meeting recordings (> 15 minutes) by partitioning audio
into overlapping intervals, transcribing each with Voxtral 4B, and stitching
transcripts with boundary timestamp alignment.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .voxtral_service import VoxtralSpeechEngine

logger = logging.getLogger("deskmate.chunked_transcriber")

CHUNK_THRESHOLD_SECONDS = 900.0   # 15 minutes
CHUNK_SIZE_SECONDS = 600.0        # 10 minute chunks
OVERLAP_SECONDS = 4.0             # 4 seconds overlap boundary


@dataclass
class AudioChunk:
    index: int
    path: str
    start_offset: float
    duration: float


class ChunkedTranscriber:
    """Manages long audio files via overlapping chunks for Voxtral 4B."""

    def __init__(self, voxtral_engine: VoxtralSpeechEngine):
        self.engine = voxtral_engine

    async def transcribe_long_file(self, audio_path: str) -> Dict[str, Any]:
        """Transcribe short files directly, or partition long files into chunks."""
        if not Path(audio_path).exists():
            return {
                "full_transcript": "",
                "segments": [],
                "duration_seconds": 0.0,
                "language": "en",
            }

        total_duration = self._get_audio_duration(audio_path)
        if total_duration < CHUNK_THRESHOLD_SECONDS:
            return await self.engine.transcribe_file(audio_path)

        logger.info(f"Audio exceeds {CHUNK_THRESHOLD_SECONDS}s ({total_duration:.1f}s). Starting chunked Voxtral processing...")
        chunks = self._split_audio(audio_path, total_duration)

        all_segments = []
        transcript_parts = []

        for chunk in chunks:
            chunk_res = await self.engine.transcribe_file(chunk.path)
            # Offset segment timestamps
            for seg in chunk_res.get("segments", []):
                all_segments.append({
                    "start": round(seg.get("start", 0.0) + chunk.start_offset, 2),
                    "end": round(seg.get("end", 0.0) + chunk.start_offset, 2),
                    "speaker": seg.get("speaker", "Speaker 1"),
                    "text": seg.get("text", "").strip(),
                })
            t_text = chunk_res.get("full_transcript", "").strip()
            if t_text:
                transcript_parts.append(t_text)

            # Cleanup temporary chunk file
            try:
                chunk_p = Path(chunk.path)
                if chunk_p.exists() and str(chunk_p) != str(Path(audio_path)):
                    chunk_p.unlink(missing_ok=True)
            except Exception as e:
                logger.debug(f"Failed to unlink temp chunk file {chunk_p}: {e}")

        return {
            "full_transcript": " ".join(transcript_parts),
            "segments": all_segments,
            "duration_seconds": total_duration,
            "language": "en",
        }

    def _get_audio_duration(self, audio_path: str) -> float:
        try:
            import soundfile as sf
            info = sf.info(audio_path)
            return float(info.duration)
        except Exception:
            size = Path(audio_path).stat().st_size
            return max(1.0, size / 32000.0)

    def _split_audio(self, audio_path: str, total_duration: float) -> List[AudioChunk]:
        """Slice audio into chunks with overlap using soundfile."""
        chunks = []
        try:
            import soundfile as sf

            data, sr = sf.read(audio_path)
            step_samples = int((CHUNK_SIZE_SECONDS - OVERLAP_SECONDS) * sr)
            chunk_samples = int(CHUNK_SIZE_SECONDS * sr)
            total_samples = len(data)

            idx = 0
            start_samp = 0
            base_dir = Path(audio_path).parent

            while start_samp < total_samples:
                end_samp = min(start_samp + chunk_samples, total_samples)
                chunk_data = data[start_samp:end_samp]
                chunk_file = str(base_dir / f"temp_chunk_{idx}.wav")
                sf.write(chunk_file, chunk_data, sr)

                chunks.append(AudioChunk(
                    index=idx,
                    path=chunk_file,
                    start_offset=start_samp / float(sr),
                    duration=len(chunk_data) / float(sr),
                ))
                idx += 1
                start_samp += step_samples

        except Exception as e:
            logger.warning(f"Audio splitting error: {e}. Falling back to single chunk.")
            chunks = [AudioChunk(index=0, path=audio_path, start_offset=0.0, duration=total_duration)]

        return chunks
