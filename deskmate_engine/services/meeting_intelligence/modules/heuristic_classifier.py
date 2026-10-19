import cv2
import numpy as np
import logging

logger = logging.getLogger(__name__)

class HeuristicUIClassifier:
    """Classifies UI elements using geometric rules and color heuristics."""
    
    def classify(self, roi_frame):
        """Returns (class_name, confidence)"""
        if roi_frame is None or roi_frame.size == 0:
            return "unknown", 0.0
            
        h, w = roi_frame.shape[:2]
        aspect_ratio = w / h if h > 0 else 0
        
        # 1. Error Detection (Red color presence)
        if self._check_red_presence(roi_frame):
            return "error_state", 0.85

        # 2. Heuristic: Input Field (Long horizontal box)
        if 4.0 < aspect_ratio < 15.0 and 30 < h < 100:
            return "input_field", 0.75

        # 3. Heuristic: Button (Wide rectangle)
        if 1.5 < aspect_ratio < 4.0 and 20 < h < 80:
            return "button", 0.70

        # 4. Heuristic: Modal / Dialog (Large centered box)
        if 0.8 < aspect_ratio < 1.5 and w > 400 and h > 300:
            return "modal_window", 0.80

        return "unclassified", 0.1

    def _check_red_presence(self, roi_frame):
        """Detects error states via red pixel density."""
        hsv = cv2.cvtColor(roi_frame, cv2.COLOR_BGR2HSV)
        
        # Define range for red color
        lower_red1 = np.array([0, 70, 50])
        upper_red1 = np.array([10, 255, 255])
        lower_red2 = np.array([170, 70, 50])
        upper_red2 = np.array([180, 255, 255])
        
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)
        red_mask = cv2.bitwise_or(mask1, mask2)
        
        red_ratio = np.count_nonzero(red_mask) / (roi_frame.shape[0] * roi_frame.shape[1])
        return red_ratio > 0.15 # >15% red pixels likely an error banner/border
