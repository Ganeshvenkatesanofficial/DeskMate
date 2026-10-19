"""
services.meeting_intelligence.locate_anything — NVIDIA LocateAnything-3B Subsystem
===================================================================================
Exports the NVIDIA LocateAnything-3B Parallel Box Decoding detector.
"""

from .modules.locate_anything import LocateAnythingDetector

# Public API alias
LocateAnythingGrounding = LocateAnythingDetector

__all__ = ["LocateAnythingDetector", "LocateAnythingGrounding"]
