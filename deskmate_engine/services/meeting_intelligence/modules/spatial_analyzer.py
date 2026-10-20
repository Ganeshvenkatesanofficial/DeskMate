import cv2
import numpy as np
import logging
from .. import config

logger = logging.getLogger(__name__)

class SpatialAnalyzer:
    """Enforces Hard Safety Masks and Dynamic Sidebar Detection."""
    
    def __init__(self):
        self.sidebar_active = False

    def detect_sidebar(self, frame_bgr):
        """Heuristic: Too many edges/active blocks in the right 25% -> Sidebar."""
        h, w = frame_bgr.shape[:2]
        right_roi = frame_bgr[:, int(0.75 * w):]
        
        gray = cv2.cvtColor(right_roi, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, 50, 150)
        edge_density = np.count_nonzero(edges) / (right_roi.shape[0] * right_roi.shape[1])
        
        # Heuristic: participant tiles/chat have high edge density compared to main content
        self.sidebar_active = edge_density > 0.05
        return self.sidebar_active

    def get_safety_mask(self, h, w):
        """Generates the Hard Safety Mask image."""
        mask = np.ones((h, w), dtype=np.uint8) * 255
        
        # Ignore Tops/Bottoms
        top_h = int(h * config.IGNORE_TOP_PCT)
        bot_h = int(h * config.IGNORE_BOTTOM_PCT)
        mask[0:top_h, :] = 0
        mask[h-bot_h:h, :] = 0
        
        # Ignore Left
        left_w = int(w * config.IGNORE_LEFT_PCT)
        mask[:, 0:left_w] = 0
        
        # Ignore Right (Dynamic)
        r_pct = config.IGNORE_RIGHT_PCT_MAX if self.sidebar_active else config.IGNORE_RIGHT_PCT_MIN
        right_w = int(w * r_pct)
        mask[:, w-right_w:w] = 0
        
        return mask
