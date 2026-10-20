"""
services.meeting_intelligence.utils — Hardware Detection & Telemetry Utilities
==============================================================================
"""

from .hardware_check import get_inference_device

__all__ = [
    "get_inference_device",
]
