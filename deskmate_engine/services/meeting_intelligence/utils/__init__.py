"""
services.meeting_intelligence.utils — Hardware Detection & Telemetry Utilities
==============================================================================
"""

from .hardware_check import get_inference_device, log_hardware_status
from .logging_utils import setup_meeting_logger

__all__ = [
    "get_inference_device",
    "log_hardware_status",
    "setup_meeting_logger",
]
