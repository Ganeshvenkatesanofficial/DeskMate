"""
services.meeting_intelligence — DeskMate Meeting Intelligence Service
====================================================================
End-to-end meeting recording, Voxtral 4B speech transcription,
NVIDIA LocateAnything-3B GUI grounding, multimodal Gemini 2.5 Flash / Ollama
summarization, and DeskMate-branded executive PDF generation.
"""

from .screen_capture import ScreenCapture
from .modules.locate_anything import LocateAnythingDetector
from .live_pipeline import LivePipeline
from .summarizer import MeetingSummarizer
from .pdf_generator import MeetingPDFGenerator
from .export_service import MeetingExportService
from .transcriber import VoxtralSpeechEngine, AudioExtractor, ChunkedTranscriber
from .utils import get_inference_device

__all__ = [
    "ScreenCapture",
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

