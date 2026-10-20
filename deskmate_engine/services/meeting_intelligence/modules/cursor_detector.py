import cv2
import numpy as np
import logging
import os
from collections import deque
from pathlib import Path
from .. import config

logger = logging.getLogger(__name__)

class CursorDetector:
    """Detects cursor while strictly obeying the Hard Safety Mask."""
    
    def __init__(self):
        self.templates = self._load_or_generate_templates()
        self.pos_history = deque(maxlen=config.CURSOR_SMOOTHING_WINDOW)
        self.scales = config.CURSOR_SCALES

    def detect(self, frame_bgr, safety_mask=None):
        """Returns (x, y) if found in the non-masked region."""
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        
        # Apply mask if provided
        if safety_mask is not None:
            gray = cv2.bitwise_and(gray, gray, mask=safety_mask)

        best_val = -1
        best_loc = None
        best_type = None
        best_tw, best_th = 0, 0

        for name, template in self.templates.items():
            for scale in self.scales:
                t_w = int(template.shape[1] * scale)
                t_h = int(template.shape[0] * scale)
                scaled_t = cv2.resize(template, (t_w, t_h))

                res = cv2.matchTemplate(gray, scaled_t, cv2.TM_CCOEFF_NORMED)
                _, max_val, _, max_loc = cv2.minMaxLoc(res)

                if max_val > best_val:
                    best_val = max_val
                    best_loc = max_loc
                    best_type = name
                    best_tw, best_th = t_w, t_h

        if best_val >= config.CURSOR_MATCH_THRESHOLD:
            tw, th = best_tw, best_th
            raw_pos = (best_loc[0] + tw // 2, best_loc[1] + th // 2)
            
            self.pos_history.append(raw_pos)
            avg_x = int(np.mean([p[0] for p in self.pos_history]))
            avg_y = int(np.mean([p[1] for p in self.pos_history]))
            
            return (avg_x, avg_y), best_type
            
        if self.pos_history:
            self.pos_history.popleft()
            
        return None, None

    def _load_or_generate_templates(self):
        templates = {}
        tmpl_dir = Path(config.CURSOR_TEMPLATES_DIR)
        if tmpl_dir.exists():
            for f in tmpl_dir.iterdir():
                if f.suffix.lower() in ('.png', '.jpg'):
                    templates[f.stem] = cv2.imread(str(f), 0)
        if not templates:
            templates['arrow'] = self._generate_arrow_template()
            templates['hand'] = self._generate_hand_template()
        return templates

    def _generate_arrow_template(self):
        img = np.zeros((32, 32), dtype=np.uint8)
        pts = np.array([[2, 2], [22, 12], [12, 12], [12, 22]], np.int32)
        cv2.fillPoly(img, [pts], 255)
        cv2.polylines(img, [pts], True, 0, 2)
        return img

    def _generate_hand_template(self):
        img = np.zeros((32, 32), dtype=np.uint8)
        cv2.circle(img, (16, 16), 10, 255, -1)
        cv2.polylines(img, [np.array([[16, 2], [16, 16]])], False, 0, 3)
        return img
