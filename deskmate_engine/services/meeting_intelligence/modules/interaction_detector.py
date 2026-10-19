import logging
import numpy as np
from .. import config

logger = logging.getLogger(__name__)

class InteractionDetector:
    """Detects events while strictly eliminating redundant 'same location' captures."""
    
    def __init__(self):
        self.last_stable_pos = None
        self.frames_stable = 0
        self.last_event_time = 0
        self.last_event_pos = None

    def detect_interactions(self, cursor_pos, has_visual_change, timestamp, motion_patch=None):
        """
        Detects interactions with a strict 2s spatial-temporal cooldown.
        """
        if cursor_pos is None:
            return []

        # 1. Global Cooldown (Strict 2s)
        time_since_last = (timestamp - self.last_event_time) * 1000
        if time_since_last < config.EVENT_COOLDOWN_MS:
            # Check if it's the SAME position. If so, definitely skip.
            if self.last_event_pos is not None:
                dist = np.linalg.norm(np.array(cursor_pos) - np.array(self.last_event_pos))
                if dist < 50: # Same functional area
                    return []

        # 2. Update Stability
        if self.last_stable_pos is not None:
            dist = np.linalg.norm(np.array(cursor_pos) - np.array(self.last_stable_pos))
            if dist < config.STABLE_CURSOR_MAX_MOVE:
                self.frames_stable += 1
            else:
                self.frames_stable = 0
                self.last_stable_pos = cursor_pos
        else:
            self.last_stable_pos = cursor_pos
            self.frames_stable = 0

        interactions = []
        
        # 3. Decision Logic (Click requires stability + visual change)
        if self.frames_stable >= config.CLICK_WINDOW_FRAMES and has_visual_change:
            interactions.append("click")
            self.last_event_time = timestamp
            self.last_event_pos = cursor_pos
            self.frames_stable = 0 

        return list(set(interactions))
