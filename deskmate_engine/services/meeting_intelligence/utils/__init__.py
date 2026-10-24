"""
services.meeting_intelligence.utils — Hardware Detection & Telemetry Utilities
==============================================================================
"""

from .hardware_check import get_inference_device, get_mps_lock

__all__ = [
    "get_inference_device",
    "get_mps_lock",
]
