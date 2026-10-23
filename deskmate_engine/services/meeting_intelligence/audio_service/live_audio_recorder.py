"""
services.meeting_intelligence.transcriber.live_audio_recorder
=============================================================
Automated background meeting audio recording with dynamic microphone
mute control and native system output capture (Speakers, Bluetooth earphones,
AirPods, and 3.5mm audio jack).
"""

from __future__ import annotations

import os
import sys
import time
import shutil
import logging
import platform
import threading
import subprocess
from pathlib import Path
from typing import Any, Optional
import numpy as np
import sounddevice as sd
import soundfile as sf

logger = logging.getLogger("deskmate.audio_recorder")

SAMPLE_RATE = 16000  # Voxtral native target rate
CHANNELS = 1         # Mono
# The helper can block on the macOS Screen Recording permission prompt.
HELPER_READY_TIMEOUT_SECONDS = 8.0


def _read_line_with_timeout(stream: Any, timeout: float) -> Optional[str]:
    """Read one line from a pipe, giving up after `timeout` seconds."""
    result: list[str] = []
    reader = threading.Thread(target=lambda: result.append(stream.readline()), daemon=True)
    reader.start()
    reader.join(timeout)
    return result[0].strip() if result else None


def _find_macos_helper() -> Optional[str]:
    """Locate the native macOS ScreenCaptureKit audio capture helper binary.
    
    IMPORTANT: macOS TCC (Screen & System Audio permissions) are strictly tied
    to the permanent, persistent path of the binary. Temporary directories
    (like sys._MEIPASS in /var/folders/...) have randomized paths on every launch
    and are rejected by macOS TCC. Therefore, the stable installed binary in
    Application Support / DeskMate / bin MUST be prioritized first.
    """
    search_paths = [
        # 1. Primary: Persistent stable path installed by DeskMate
        Path.home() / "Library" / "Application Support" / "DeskMate" / "bin" / "macos_audio_capture",
        # 2. Bundle / Local development helpers
        Path(sys.executable).parent / "macos_audio_capture",
        Path(sys.executable).parent / "helpers" / "macos_audio_capture",
        Path(__file__).resolve().parent / "macos_audio_capture",
        Path(__file__).resolve().parent.parent.parent.parent / "helpers" / "macos_audio_capture",
    ]

    # 3. Last fallback: unpacked PyInstaller bundle
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        search_paths.append(Path(sys._MEIPASS) / "helpers" / "macos_audio_capture")
        search_paths.append(Path(sys._MEIPASS) / "macos_audio_capture")

    which_helper = shutil.which("macos_audio_capture")
    if which_helper:
        search_paths.append(Path(which_helper))

    for p in search_paths:
        if p.is_file() and os.access(str(p), os.X_OK):
            logger.info(f"Found native macOS audio capture helper at: {p}")
            return str(p)

    return None


class LiveAudioRecorder:
    """
    Automated background audio recorder capturing system output (speakers, Bluetooth
    earphones, audio jack) and microphone audio.
    Supports real-time mic muting so ambient room voices are strictly blocked
    when muted, while meeting output audio is continuously captured.
    """

    def __init__(self, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.is_recording = False
        self.is_muted = False
        self.system_audio_active = False
        self.mic_audio_active = False
        self.warning: str | None = None

        # Output paths
        self._output_path: str | None = None
        self._system_wav_path: str | None = None
        self._mic_wav_path: str | None = None

        # System output capture
        self._macos_proc: subprocess.Popen | None = None
        self._win_system_stream: sd.InputStream | None = None
        self._win_system_wav: sf.SoundFile | None = None

        # Microphone capture
        self._mic_stream: sd.InputStream | None = None
        self._mic_wav: sf.SoundFile | None = None

        # Metrics
        self._start_time: float | None = None
        self._frames_written = 0
        self._lock = threading.Lock()

    def _find_input_device(self) -> int | None:
        """Find active system microphone device."""
        try:
            default_in = sd.default.device[0]
            if default_in is not None and default_in >= 0:
                devices = sd.query_devices()
                logger.info(f"Using default input/mic device index {default_in}: {devices[default_in].get('name')}")
                return default_in
        except Exception as e:
            logger.warning(f"Audio device query warning: {e}")
        return None

    def _find_wasapi_loopback_device(self) -> int | None:
        """Find Windows WASAPI default render/output device for loopback capture."""
        try:
            devices = sd.query_devices()
            apis = sd.query_hostapis()
            wasapi_idx = None
            for idx, api in enumerate(apis):
                if "wasapi" in api.get("name", "").lower():
                    wasapi_idx = idx
                    break

            if wasapi_idx is not None:
                default_out = apis[wasapi_idx].get("default_output_device")
                if default_out is not None and default_out >= 0:
                    logger.info(f"Using Windows WASAPI loopback device {default_out}: {devices[default_out].get('name')}")
                    return default_out
        except Exception as e:
            logger.warning(f"WASAPI device query warning: {e}")
        return None

    def start_recording(self, session_dir: str, filename: str = "audio.wav", start_muted: bool = False) -> str:
        """
        Start dual-stream background audio capture:
        1. System audio (Speakers / Bluetooth earphones / Audio jack).
        2. Microphone (dynamically muted or unmuted).
        """
        with self._lock:
            if self.is_recording:
                return self._output_path or ""

            Path(session_dir).mkdir(parents=True, exist_ok=True)
            self._output_path = str(Path(session_dir) / filename)
            self._system_wav_path = str(Path(session_dir) / "system_audio.wav")
            self._mic_wav_path = str(Path(session_dir) / "mic_audio.wav")
            self._start_time = time.time()
            self._frames_written = 0
            self.is_muted = start_muted

            system_started = False

            # --- 1. Start System Audio Capture (Speakers, Bluetooth, Audio Jack) ---
            current_os = platform.system().lower()
            if "darwin" in current_os:
                helper = _find_macos_helper()
                if helper:
                    try:
                        self._macos_proc = subprocess.Popen(
                            [helper, self._system_wav_path],
                            stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                        )
                        ready_line = None
                        if self._macos_proc.stdout:
                            ready_line = _read_line_with_timeout(
                                self._macos_proc.stdout, HELPER_READY_TIMEOUT_SECONDS
                            )
                        if ready_line and "READY" in ready_line:
                            logger.info("macOS native system audio capture started successfully.")
                            system_started = True
                        else:
                            proc = self._macos_proc
                            # Stop it first: reading stderr of a live process blocks forever.
                            self._stop_macos_helper()
                            err_msg = ""
                            try:
                                err_msg = (proc.stderr.read() if proc.stderr else "").strip()
                            except Exception:
                                pass
                            logger.warning(
                                f"macOS audio helper did not confirm READY (output: {ready_line!r}"
                                + (f", stderr: {err_msg!r}" if err_msg else "")
                                + ")."
                            )
                    except Exception as e:
                        logger.warning(f"Could not launch macOS audio capture helper: {e}")
                        self._macos_proc = None
                else:
                    logger.warning("macOS audio capture helper not found; recording microphone only.")

            elif "windows" in current_os:
                wasapi_dev = self._find_wasapi_loopback_device()
                if wasapi_dev is not None and hasattr(sd, "WasapiSettings"):
                    try:
                        dev_info = sd.query_devices(wasapi_dev)
                        loopback_sr = int(dev_info.get("default_samplerate", 48000))
                        loopback_channels = min(int(dev_info.get("max_output_channels", 2)), 2) or 2

                        self._win_system_wav = sf.SoundFile(
                            self._system_wav_path,
                            mode="w",
                            samplerate=loopback_sr,
                            channels=CHANNELS,
                            subtype="PCM_16",
                        )

                        def win_loopback_callback(indata, frames, time_info, status):
                            if not self.is_recording or not self._win_system_wav:
                                return
                            # If stereo, convert to mono
                            if indata.ndim > 1 and indata.shape[1] > 1:
                                mono = np.mean(indata, axis=1, keepdims=True).astype(np.int16)
                                self._win_system_wav.write(mono)
                            else:
                                self._win_system_wav.write(indata)

                        self._win_system_stream = sd.InputStream(
                            samplerate=loopback_sr,
                            channels=loopback_channels,
                            dtype="int16",
                            device=wasapi_dev,
                            extra_settings=sd.WasapiSettings(loopback=True),
                            callback=win_loopback_callback,
                        )
                        self._win_system_stream.start()
                        system_started = True
                        logger.info(
                            f"Windows WASAPI loopback audio capture started successfully "
                            f"({loopback_sr}Hz, {loopback_channels}ch)."
                        )
                    except Exception as e:
                        logger.warning(f"Failed to start Windows WASAPI loopback: {e}")
                        self._win_system_stream = None

            # --- 2. Start Microphone Stream ---
            mic_dev = self._find_input_device()
            try:
                # If system capture could not start, mic stream will write directly to final output
                mic_target_path = self._mic_wav_path if system_started else self._output_path
                self._mic_wav = sf.SoundFile(
                    mic_target_path,
                    mode="w",
                    samplerate=self.sample_rate,
                    channels=CHANNELS,
                    subtype="PCM_16",
                )

                def mic_callback(indata, frames, time_info, status):
                    if not self.is_recording or not self._mic_wav:
                        return
                    if self.is_muted:
                        # When mic is muted, write silence to mic track so room voices are blocked
                        zeros = np.zeros_like(indata)
                        self._mic_wav.write(zeros)
                    else:
                        self._mic_wav.write(indata)
                    self._frames_written += frames

                self._mic_stream = sd.InputStream(
                    samplerate=self.sample_rate,
                    channels=CHANNELS,
                    dtype="int16",
                    device=mic_dev,
                    callback=mic_callback,
                )
                self._mic_stream.start()
                self.mic_audio_active = True
                self.is_recording = True
                logger.info(
                    f"LiveAudioRecorder active. System capture: {system_started}, "
                    f"Mic device: {mic_dev}, Mic muted: {self.is_muted}"
                )
            except Exception as e:
                logger.error(f"Failed to start microphone stream: {e}")
                self.is_recording = system_started
            finally:
                self.system_audio_active = system_started
                self.warning = self._build_warning()
            return self._output_path if self.is_recording else ""

    def _build_warning(self) -> str | None:
        is_mac = "darwin" in platform.system().lower()
        speaker_fix = (
            "allow Screen Recording for DeskMate in System Settings > Privacy & Security"
            if is_mac
            else "check that a speaker or headset output device is active"
        )
        if not self.system_audio_active and not self.mic_audio_active:
            return f"No audio is being recorded. Allow Microphone access and {speaker_fix}."
        if not self.system_audio_active:
            if self.is_muted:
                return f"Speaker audio could not start and the mic is muted, so this recording will be silent. Unmute the mic, or {speaker_fix}."
            return f"Speaker audio could not start, so only your microphone is recorded. To capture other attendees, {speaker_fix}."
        if not self.mic_audio_active:
            return "Microphone could not start, so only speaker audio is recorded. Allow Microphone access for DeskMate."
        return None

    def _stop_macos_helper(self) -> None:
        proc = self._macos_proc
        self._macos_proc = None
        if not proc:
            return
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            try:
                proc.kill()
                proc.wait(timeout=2.0)
            except Exception:
                pass

    def set_muted(self, muted: bool) -> bool:
        """Toggle microphone mute state in real time."""
        with self._lock:
            self.is_muted = muted
            logger.info(f"LiveAudioRecorder mic muted set to: {muted}")
            return self.is_muted

    def stop_recording(self) -> Optional[str]:
        """Stop background audio capture and mix system + mic audio into final audio.wav."""
        with self._lock:
            if not self.is_recording:
                return self._output_path

            self.is_recording = False

            # 1. Stop macOS system audio capture helper
            if self._macos_proc:
                try:
                    if self._macos_proc.stdin:
                        self._macos_proc.stdin.write("stop\n")
                        self._macos_proc.stdin.flush()
                        self._macos_proc.stdin.close()
                    self._macos_proc.wait(timeout=2.0)
                except Exception as e:
                    logger.debug(f"macOS helper stop timeout/error: {e}")
                    try:
                        self._macos_proc.terminate()
                    except Exception:
                        pass
                self._macos_proc = None

            # 2. Stop Windows WASAPI loopback stream
            if self._win_system_stream:
                try:
                    self._win_system_stream.stop()
                    self._win_system_stream.close()
                except Exception as e:
                    logger.debug(f"WASAPI stream close error: {e}")
                self._win_system_stream = None

            if self._win_system_wav:
                try:
                    self._win_system_wav.flush()
                    self._win_system_wav.close()
                except Exception as e:
                    logger.debug(f"WASAPI wav close error: {e}")
                self._win_system_wav = None

            # 3. Stop Microphone stream
            if self._mic_stream:
                try:
                    self._mic_stream.stop()
                    self._mic_stream.close()
                except Exception as e:
                    logger.debug(f"Mic stream close error: {e}")
                self._mic_stream = None

            if self._mic_wav:
                try:
                    self._mic_wav.flush()
                    self._mic_wav.close()
                except Exception as e:
                    logger.debug(f"Mic wav close error: {e}")
                self._mic_wav = None

            # 4. Mix system audio + mic audio into final output
            self._finalize_mixed_audio()

            duration = round(time.time() - self._start_time, 2) if self._start_time else 0.0
            logger.info(f"LiveAudioRecorder finalized: {self._output_path} ({duration}s)")
            return self._output_path

    def _resample(self, data: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        """Resample audio array to target sample rate."""
        if orig_sr == target_sr or len(data) == 0:
            return data
        try:
            import math
            from scipy import signal
            gcd = math.gcd(orig_sr, target_sr)
            up = target_sr // gcd
            down = orig_sr // gcd
            resampled = signal.resample_poly(data, up, down)
            return np.clip(resampled, -32768, 32767).astype(np.int16)
        except Exception:
            old_indices = np.arange(len(data))
            new_indices = np.linspace(0, len(data) - 1, int(len(data) * target_sr / orig_sr))
            return np.interp(new_indices, old_indices, data).astype(np.int16)

    def _finalize_mixed_audio(self) -> None:
        """Combine system audio and mic audio into final audio.wav file."""
        sys_file = Path(self._system_wav_path) if self._system_wav_path else None
        mic_file = Path(self._mic_wav_path) if self._mic_wav_path else None
        out_file = Path(self._output_path) if self._output_path else None

        if not out_file:
            return

        has_sys = sys_file and sys_file.is_file() and sys_file.stat().st_size > 44
        has_mic = mic_file and mic_file.is_file() and mic_file.stat().st_size > 44

        try:
            if has_sys and has_mic:
                sys_data, sr_sys = sf.read(str(sys_file), dtype="int16")
                mic_data, sr_mic = sf.read(str(mic_file), dtype="int16")

                # Ensure 1D mono arrays
                if sys_data.ndim > 1:
                    sys_data = np.mean(sys_data, axis=1).astype(np.int16)
                if mic_data.ndim > 1:
                    mic_data = np.mean(mic_data, axis=1).astype(np.int16)

                # Resample to target sample rate if needed
                if sr_sys != self.sample_rate:
                    sys_data = self._resample(sys_data, sr_sys, self.sample_rate)
                if sr_mic != self.sample_rate:
                    mic_data = self._resample(mic_data, sr_mic, self.sample_rate)

                max_len = max(len(sys_data), len(mic_data))
                if len(sys_data) < max_len:
                    sys_data = np.pad(sys_data, (0, max_len - len(sys_data)))
                if len(mic_data) < max_len:
                    mic_data = np.pad(mic_data, (0, max_len - len(mic_data)))

                # Mix with int16 clipping to prevent overflow distortion
                mixed = np.clip(
                    sys_data.astype(np.int32) + mic_data.astype(np.int32),
                    -32768,
                    32767,
                ).astype(np.int16)

                sf.write(str(out_file), mixed, self.sample_rate, subtype="PCM_16")
                logger.info(f"Successfully mixed {len(mixed)} frames into {out_file}")

                # Clean up intermediate files
                try:
                    sys_file.unlink(missing_ok=True)
                    mic_file.unlink(missing_ok=True)
                except Exception:
                    pass

            elif has_sys:
                sys_data, sr_sys = sf.read(str(sys_file), dtype="int16")
                if sys_data.ndim > 1:
                    sys_data = np.mean(sys_data, axis=1).astype(np.int16)
                if sr_sys != self.sample_rate:
                    sys_data = self._resample(sys_data, sr_sys, self.sample_rate)
                sf.write(str(out_file), sys_data, self.sample_rate, subtype="PCM_16")
                try:
                    sys_file.unlink(missing_ok=True)
                except Exception:
                    pass
                logger.info(f"Used system audio as primary recording: {out_file}")

            elif has_mic:
                mic_data, sr_mic = sf.read(str(mic_file), dtype="int16")
                if mic_data.ndim > 1:
                    mic_data = np.mean(mic_data, axis=1).astype(np.int16)
                if sr_mic != self.sample_rate:
                    mic_data = self._resample(mic_data, sr_mic, self.sample_rate)
                sf.write(str(out_file), mic_data, self.sample_rate, subtype="PCM_16")
                try:
                    mic_file.unlink(missing_ok=True)
                except Exception:
                    pass
                logger.info(f"Used microphone audio as primary recording: {out_file}")
        except Exception as e:
            logger.error(f"Error finalizing audio mix: {e}")

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
