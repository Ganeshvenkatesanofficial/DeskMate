"""
modules.decision_gate — Neural Grounding Decision Gate
======================================================
Determines whether high-confidence heuristic contour analysis is sufficient,
or if NVIDIA LocateAnything-3B neural visual grounding is required.
"""

import logging

logger = logging.getLogger("deskmate.decision_gate")


class DecisionGate:
    """Decides if the pipeline needs neural visual grounding (LocateAnything-3B) or can rely on heuristics."""

    def __init__(self, confidence_threshold: float = 0.80):
        self.confidence_threshold = confidence_threshold

    def needs_grounding(self, heuristic_label: str, heuristic_conf: float) -> bool:
        """Returns True if LocateAnything-3B is required for visual grounding."""
        if heuristic_conf >= self.confidence_threshold:
            logger.debug(f"DecisionGate: Skipping neural grounding (Heuristic confident: {heuristic_label} @ {heuristic_conf:.2f})")
            return False

        logger.debug(f"DecisionGate: LocateAnything-3B required (Heuristic uncertain: {heuristic_conf:.2f})")
        return True

    # Backwards compatibility alias
    needs_dino = needs_grounding
