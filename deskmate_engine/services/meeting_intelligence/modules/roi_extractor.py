import cv2
import logging
from .. import config

logger = logging.getLogger(__name__)

class ActionCentricROIExtractor:
    """Action-aware ROI extraction with floating overlay rejection."""
    
    def __init__(self):
        self.base_w, self.base_h = config.ROI_SIZE

    def extract_relevant_roi(self, frame_bgr, cursor_pos, motion_mask, safety_mask=None):
        """
        Extracts a 16:9 crop centered on the action (cursor, motion, or screen center).
        """
        img_h, img_w = frame_bgr.shape[:2]
        
        # Apply safety mask to motion if provided
        if safety_mask is not None and motion_mask is not None:
            motion_mask = cv2.bitwise_and(motion_mask, motion_mask, mask=safety_mask)

        # 1. Determine Target Center
        cx, cy = None, None
        if cursor_pos is not None: 
            cx, cy = cursor_pos
            # Refine center based on local motion near cursor
            if motion_mask is not None:
                mx1 = max(0, cx - 200)
                my1 = max(0, cy - 200)
                mx2 = min(img_w, cx + 200)
                my2 = min(img_h, cy + 200)
                local_mask = motion_mask[my1:my2, mx1:mx2]
                M = cv2.moments(local_mask)
                if M["m00"] > 0:
                    cx = int(M["m10"] / M["m00"]) + mx1
                    cy = int(M["m01"] / M["m00"]) + my1

        # Fallback when hardware cursor is not captured (macOS hardware cursor or presentations)
        if cx is None or cy is None:
            if motion_mask is not None:
                M = cv2.moments(motion_mask)
                if M["m00"] > 0:
                    cx = int(M["m10"] / M["m00"])
                    cy = int(M["m01"] / M["m00"])
            if cx is None or cy is None:
                cx = img_w // 2
                cy = img_h // 2

        # 2. Size & Adaptive Crop
        target_w, target_h = self.base_w, self.base_h
        
        if motion_mask is not None:
            contours, _ = cv2.findContours(motion_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if contours:
                largest = max(contours, key=cv2.contourArea)
                x, y, w, h = cv2.boundingRect(largest)
                if w > self.base_w or h > self.base_h:
                    target_w = min(img_w, int(w * config.ROI_ADAPTIVE_EXPAND))
                    target_h = min(img_h, int(target_w / config.ROI_ASPECT_RATIO))
        
        min_w, min_h = config.ROI_MIN_SIZE
        target_w = min(img_w, max(min_w, target_w))
        target_h = min(img_h, max(min_h, target_h))

        # 3. Final BBox & Frame fitting
        x1 = max(0, min(cx - target_w // 2, img_w - target_w))
        y1 = max(0, min(cy - target_h // 2, img_h - target_h))
        x2 = min(img_w, x1 + target_w)
        y2 = min(img_h, y1 + target_h)

        crop = frame_bgr[y1:y2, x1:x2].copy()
        if crop.size == 0:
            return frame_bgr.copy(), [0, 0, img_w, img_h]
        return crop, [x1, y1, x2, y2]
