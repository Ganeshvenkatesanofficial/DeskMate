import cv2
import numpy as np
import ctypes
import logging
import sys
from collections import deque
from pathlib import Path
from .. import config

logger = logging.getLogger(__name__)


class _CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]


class _CGRect(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("w", ctypes.c_double), ("h", ctypes.c_double)]


class _WinPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


def _load_core_graphics():
    """CoreGraphics bindings, loaded once (None off macOS or if unavailable)."""
    if sys.platform != "darwin":
        return None
    try:
        cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        cg.CGEventCreate.restype = ctypes.c_void_p
        cg.CGEventCreate.argtypes = [ctypes.c_void_p]
        cg.CGEventGetLocation.restype = _CGPoint
        cg.CGEventGetLocation.argtypes = [ctypes.c_void_p]
        cg.CFRelease.argtypes = [ctypes.c_void_p]
        cg.CGMainDisplayID.restype = ctypes.c_uint32
        cg.CGDisplayBounds.restype = _CGRect
        cg.CGDisplayBounds.argtypes = [ctypes.c_uint32]
        return cg
    except Exception as e:
        logger.debug(f"CoreGraphics unavailable for cursor tracking: {e}")
        return None


_CORE_GRAPHICS = _load_core_graphics()


def _hardware_cursor_position(frame_shape) -> tuple[int, int] | None:
    """OS mouse position mapped to frame pixels (primary display), or None."""
    h, w = frame_shape[:2]
    try:
        if _CORE_GRAPHICS is not None:
            evt = _CORE_GRAPHICS.CGEventCreate(None)
            if not evt:
                return None
            loc = _CORE_GRAPHICS.CGEventGetLocation(evt)
            _CORE_GRAPHICS.CFRelease(evt)
            # Mouse is in display points; frames may be captured at a different (Retina) scale.
            bounds = _CORE_GRAPHICS.CGDisplayBounds(_CORE_GRAPHICS.CGMainDisplayID())
            scale = w / bounds.w if bounds.w else 1.0
            x, y = int(loc.x * scale), int(loc.y * scale)
        elif sys.platform == "win32":
            pt = _WinPoint()
            if not ctypes.windll.user32.GetCursorPos(ctypes.byref(pt)):
                return None
            x, y = int(pt.x), int(pt.y)
        else:
            return None
    except Exception:
        return None
    return (x, y) if 0 <= x < w and 0 <= y < h else None

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

        # Fallback: the OS cursor position (the macOS cursor is often not in screen captures).
        hw_pos = _hardware_cursor_position(frame_bgr.shape)
        if hw_pos is not None and (safety_mask is None or safety_mask[hw_pos[1], hw_pos[0]] != 0):
            self.pos_history.append(hw_pos)
            avg_x = int(np.mean([p[0] for p in self.pos_history]))
            avg_y = int(np.mean([p[1] for p in self.pos_history]))
            return (avg_x, avg_y), "pointer"
            
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
