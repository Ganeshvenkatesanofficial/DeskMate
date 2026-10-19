"""
transcriber.vad — Voice Activity Detection (VAD)
================================================
Detects speech segments and filters dead silence from audio streams before
feeding chunks into the Voxtral 4B neural model.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List

logger = logging.getLogger("deskmate.vad")


class VoiceActivityDetector:
    """Detects active speech regions and filters prolonged silence."""

    def __init__(self, energy_threshold: float = 0.015, min_speech_duration_ms: int = 400):
        self.energy_threshold = energy_threshold
        self.min_speech_duration_ms = min_speech_duration_ms

    def detect_speech_segments(self, wav_path: str) -> List[Dict[str, Any]]:
        """
        Returns list of speech intervals: [{'start': float, 'end': float}]
        """
        if not os.path.exists(wav_path):
            return []

        try:
            import soundfile as sf
            import numpy as np

            audio, sr = sf.read(wav_path)
            if len(audio.shape) > 1:
                audio = np.mean(audio, axis=1)

            frame_len = int(sr * 0.03)  # 30ms window
            total_frames = len(audio) // frame_len

            speech_segments = []
            in_speech = False
            start_sec = 0.0

            for i in range(total_frames):
                frame = audio[i * frame_len : (i + 1) * frame_len]
                rms = np.sqrt(np.mean(frame**2))
                current_time = (i * frame_len) / float(sr)

                if rms > self.energy_threshold and not in_speech:
                    in_speech = True
                    start_sec = current_time
                elif rms <= self.energy_threshold and in_speech:
                    if (current_time - start_sec) >= (self.min_speech_duration_ms / 1000.0):
                        speech_segments.append({"start": round(start_sec, 2), "end": round(current_time, 2)})
                    in_speech = False

            if in_speech:
                duration = len(audio) / float(sr)
                speech_segments.append({"start": round(start_sec, 2), "end": round(duration, 2)})

            if not speech_segments:
                # Fallback to single full interval if audio is very uniform
                duration = len(audio) / float(sr)
                return [{"start": 0.0, "end": round(duration, 2)}]

            return speech_segments

        except Exception as e:
            logger.debug(f"VAD energy inspection fallback: {e}")
            return [{"start": 0.0, "end": -1.0}]
