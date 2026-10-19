"""
services.meeting_intelligence.voxtral_service — Compatibility Shim
==================================================================
Canonical location: services.meeting_intelligence.transcriber.voxtral_service
"""

from .transcriber.voxtral_service import VoxtralSpeechEngine

__all__ = ["VoxtralSpeechEngine"]
