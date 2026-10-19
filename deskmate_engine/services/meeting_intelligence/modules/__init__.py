"""
services.meeting_intelligence.modules — Computer Vision Detection Pipeline
=========================================================================
"""

from .spatial_analyzer import SpatialAnalyzer
from .change_detector import ChangeDetector
from .cursor_detector import CursorDetector
from .interaction_detector import InteractionDetector
from .roi_extractor import ActionCentricROIExtractor
from .heuristic_classifier import HeuristicUIClassifier
from .decision_gate import DecisionGate
from .tracker import TemporalTracker
from .action_inference import CursorInformedActionInference
from .step_builder import StepBuilder
from .locate_anything import LocateAnythingDetector

__all__ = [
    "SpatialAnalyzer",
    "ChangeDetector",
    "CursorDetector",
    "InteractionDetector",
    "ActionCentricROIExtractor",
    "HeuristicUIClassifier",
    "DecisionGate",
    "TemporalTracker",
    "CursorInformedActionInference",
    "StepBuilder",
    "LocateAnythingDetector",
]
