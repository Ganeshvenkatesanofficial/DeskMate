import logging

logger = logging.getLogger(__name__)

class CursorInformedActionInference:
    """Analyzes ROI classifications and cursor interactions to infer high-level actions."""
    
    def infer(self, label, interactions, track_history=None):
        """
        label: Heuristic/DINO label (e.g. 'button')
        interactions: List from InteractionDetector (e.g. ['click'])
        """
        label = label.lower()
        
        # 1. Primary rule: detected click + UI element
        if "click" in interactions:
            if "button" in label: return "click"
            if "input" in label or "search" in label or "field" in label: return "focus_input"
            if "menu" in label: return "menu_select"
            return "click"

        # 2. Logic: Typing
        if "typing_candidate" in interactions or "input" in label or "search" in label or "field" in label:
            return "typing"

        # 3. Logic: Navigation / Scroll
        if "scrolling" in interactions:
            return "scrolling"

        # 4. Logic: Errors
        if "error" in label:
            return "failure"

        # 5. Logic: Static observation
        if "modal" in label or "popup" in label:
            return "ui_notification"

        return "observed_interaction"
