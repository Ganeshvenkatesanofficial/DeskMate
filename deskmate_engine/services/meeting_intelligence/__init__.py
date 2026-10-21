"""
services.meeting_intelligence — DeskMate Meeting Intelligence Service
====================================================================
End-to-end meeting recording, dedicated screen capture service,
audio capture & speech intelligence service, NVIDIA LocateAnything-3B GUI
grounding, multimodal Gemini 2.5 Flash / Ollama summarization, and
DeskMate-branded executive PDF generation.
"""

from .screen_capture_service import ScreenCapture
from .audio_service import (
    LiveAudioRecorder,
    VoxtralSpeechEngine,
    AudioExtractor,
    ChunkedTranscriber,
)
from .modules.locate_anything import LocateAnythingDetector
from .live_pipeline import LivePipeline
from .summarizer import MeetingSummarizer
from .pdf_generator import MeetingPDFGenerator
from .export_service import MeetingExportService
from .utils import get_inference_device

__all__ = [
    "ScreenCapture",
    "LiveAudioRecorder",
    "VoxtralSpeechEngine",
    "AudioExtractor",
    "ChunkedTranscriber",
    "LocateAnythingDetector",
    "LivePipeline",
    "MeetingSummarizer",
    "MeetingPDFGenerator",
    "MeetingExportService",
    "get_inference_device",
]
