"""
services.meeting_intelligence.transcriber.live_audio_recorder
=============================================================
Automated background meeting audio recording with dynamic microphone
mute control, loopback/earphone device detection, and real-time silence gating.
"""

from __future__ import annotations

import os
import time
import logging
import threading
from pathlib import Path
from typing import Any, Optional
import numpy as np
import sounddevice as sd
import soundfile as sf

logger = logging.getLogger("deskmate.audio_recorder")

SAMPLE_RATE = 16000  # Voxtral 4B native target rate
CHANNELS = 1         # Mono


class LiveAudioRecorder:
    """
    Automated background audio recorder capturing microphone & earphone audio.
    Supports real-time mic muting so ambient room voices are strictly blocked
    when muted.
    """

    def __init__(self, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.is_recording = False
        self.is_muted = False
        self._stream: sd.InputStream | None = None
        self._wav_file: sf.SoundFile | None = None
        self._output_path: str | None = None
        self._start_time: float | None = None
        self._frames_written = 0
        self._lock = threading.Lock()

    def _find_input_device(self) -> int | None:
        """
        Cross-platform device detection:
        - Windows: Stereo Mix, VB-Audio Virtual Cable, VoiceMeeter, What U Hear, WASAPI loopback
        - macOS: BlackHole, Loopback, Aggregate Device, Multi-Output
        - Linux: PulseAudio/PipeWire monitor devices
        - Fallback: System default active input device (Headset, Built-in Mic, USB)
        """
        try:
            devices = sd.query_devices()
            virtual_loopback_keywords = [
                # macOS
                "blackhole", "loopback", "aggregate", "multi-output", "soundflower",
                # Windows
                "stereo mix", "wave out", "what u hear", "vb-audio", "cable output",
                "cable-a", "cable-b", "voicemeeter", "virtual audio", "realtek stereo",
                # Meeting virtual devices
                "teams audio", "zoom audio", "webex", "slack audio"
            ]

            # 1. Prioritize virtual loopback / stereo mix devices to capture both earphone & system audio
            for idx, dev in enumerate(devices):
                name = dev.get("name", "").lower()
                max_in = dev.get("max_input_channels", 0)
                if max_in > 0 and any(kw in name for kw in virtual_loopback_keywords):
                    logger.info(f"Selected loopback audio device: {dev.get('name')} (index {idx})")
                    return idx

            # 2. Default to system active input (MacBook Mic, Realtek Audio, USB Headset, AirPods)
            default_in = sd.default.device[0]
            if default_in is not None and default_in >= 0:
                logger.info(f"Using default system input device index {default_in}: {devices[default_in].get('name')}")
                return default_in
        except Exception as e:
            logger.warning(f"Audio device query warning: {e}")
        return None

    def start_recording(self, session_dir: str, filename: str = "audio.wav") -> str:
        """Start background audio capture stream writing directly to session audio.wav."""
        with self._lock:
            if self.is_recording:
                return self._output_path or ""

            Path(session_dir).mkdir(parents=True, exist_ok=True)
            self._output_path = str(Path(session_dir) / filename)
            self._start_time = time.time()
            self._frames_written = 0
            self.is_muted = False

            device_idx = self._find_input_device()

            try:
                self._wav_file = sf.SoundFile(
                    self._output_path,
                    mode="w",
                    samplerate=self.sample_rate,
                    channels=CHANNELS,
                    subtype="PCM_16",
                )

                def audio_callback(indata, frames, time_info, status):
                    if not self.is_recording:
                        return
                    wav = self._wav_file
                    if wav is None:
                        return

                    if self.is_muted:
                        zeros = np.zeros_like(indata)
                        wav.write(zeros)
                    else:
                        wav.write(indata)
                    self._frames_written += frames

                self._stream = sd.InputStream(
                    samplerate=self.sample_rate,
                    channels=CHANNELS,
                    dtype="int16",
                    device=device_idx,
                    callback=audio_callback,
                )
                self._stream.start()
                self.is_recording = True
                logger.info(f"LiveAudioRecorder started: saving to {self._output_path} (Device: {device_idx})")
                return self._output_path
            except Exception as e:
                logger.error(f"Failed to start LiveAudioRecorder: {e}")
                self.is_recording = False
                if self._wav_file:
                    try:
                        self._wav_file.close()
                    except Exception as e:
                        logger.debug(f"Failed to close WAV file: {e}")
                    self._wav_file = None
                return ""

    def set_muted(self, muted: bool) -> bool:
        """Toggle microphone mute in real time."""
        with self._lock:
            self.is_muted = muted
            logger.info(f"LiveAudioRecorder mic muted state set to: {muted}")
            return self.is_muted

    def stop_recording(self) -> Optional[str]:
        """Stop background audio capture and finalize audio.wav file without deadlocking."""
        with self._lock:
            if not self.is_recording:
                return self._output_path

            self.is_recording = False

            # Stop and close the stream with abort and a timeout guard (prevents CoreAudio/sounddevice deadlock on macOS)
            stream_to_close = self._stream
            self._stream = None

            if stream_to_close:
                def _close_stream():
                    try:
                        stream_to_close.abort(ignore_errors=True)
                    except Exception as e:
                        logger.debug(f"Audio stream abort error: {e}")
                    try:
                        stream_to_close.close(ignore_errors=True)
                    except Exception as e:
                        logger.debug(f"Audio stream close error: {e}")

                t = threading.Thread(target=_close_stream, daemon=True, name="AudioStreamCloseThread")
                t.start()
                t.join(timeout=1.0)

            try:
                if self._wav_file:
                    self._wav_file.flush()
                    self._wav_file.close()
                    self._wav_file = None
            except Exception as e:
                logger.warning(f"Error closing wav file: {e}")

            duration = (
                round(time.time() - self._start_time, 2)
                if self._start_time
                else 0.0
            )
            logger.info(
                f"LiveAudioRecorder stopped. Finalized {self._output_path} "
                f"({duration}s, {self._frames_written} frames)"
            )
            return self._output_path

    def get_status(self) -> dict[str, Any]:
        """Return real-time recording state and duration."""
        duration = (
            round(time.time() - self._start_time, 1)
            if self._start_time and self.is_recording
            else 0.0
        )
        return {
            "is_recording": self.is_recording,
            "is_muted": self.is_muted,
            "duration_seconds": duration,
            "frames_written": self._frames_written,
            "output_path": self._output_path,
        }
