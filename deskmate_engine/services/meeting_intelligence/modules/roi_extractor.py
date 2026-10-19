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
        Extracts 16:9 crop centered on action, rejecting tiny transient overlays.
        """
        img_h, img_w = frame_bgr.shape[:2]
        frame_area = img_w * img_h
        
        # Apply safety mask to motion if provided
        if safety_mask is not None and motion_mask is not None:
            motion_mask = cv2.bitwise_and(motion_mask, motion_mask, mask=safety_mask)

        # 1. Determine Target Center
        cx, cy = None, None
        if cursor_pos is not None: 
            cx, cy = cursor_pos
        
        # Refine center based on local motion near cursor
        if cx is not None and motion_mask is not None:
            mx1 = max(0, cx - 200)
            my1 = max(0, cy - 200)
            mx2 = min(img_w, cx + 200)
            my2 = min(img_h, cy + 200)
            local_mask = motion_mask[my1:my2, mx1:mx2]
            M = cv2.moments(local_mask)
            if M["m00"] > 0:
                cx = int(M["m10"] / M["m00"]) + mx1
                cy = int(M["m01"] / M["m00"]) + my1

        if cx is None or cy is None:
            return None, None

        # 2. Size & Floating Overlay Filter
        target_w, target_h = self.base_w, self.base_h
        
        if motion_mask is not None:
            contours, _ = cv2.findContours(motion_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if contours:
                largest = max(contours, key=cv2.contourArea)
                area = cv2.contourArea(largest)
                
                # --- Floating Overlay Filter ---
                if config.ROI_OVERLAY_MIN_PCT > 0 and area < (frame_area * config.ROI_OVERLAY_MIN_PCT):
                    logger.debug(f"ROI Discarded: Area {area/frame_area:.1%} < {config.ROI_OVERLAY_MIN_PCT:.1%}")
                    return None, None
                    
                x, y, w, h = cv2.boundingRect(largest)
                if w > self.base_w or h > self.base_h:
                    target_w = int(w * config.ROI_ADAPTIVE_EXPAND)
                    target_h = int(target_w / 1.77) # 16:9
        
        # 3. Final BBox
        x1 = max(0, cx - target_w // 2)
        y1 = max(0, cy - target_h // 2)
        x2 = min(img_w, x1 + target_w)
        y2 = min(img_h, y1 + target_h)
        
        # Frame fitting
        if x2 == img_w: x1 = max(0, x2 - target_w)
        if y2 == img_h: y1 = max(0, y2 - target_h)

        return frame_bgr[y1:y2, x1:x2].copy(), [x1, y1, x2, y2]
