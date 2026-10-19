import cv2
import numpy as np
import logging
from .. import config

logger = logging.getLogger(__name__)

try:
    from skimage.metrics import structural_similarity as skimage_ssim
    HAS_SKIMAGE = True
except ImportError:
    HAS_SKIMAGE = False

class ChangeDetector:
    """Fast dual-layer change detector: Pixel Diff + SSIM."""
    def __init__(self):
        self.prev_frame_gray = None
        self.prev_frame_small = None

    def is_candidate_frame(self, frame_bgr):
        """Returns (is_candidate, diff_score, ssim_score, motion_mask)."""
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)

        if self.prev_frame_gray is None:
            self.prev_frame_gray = gray
            self.prev_frame_small = self._get_small(gray)
            return False, 0.0, 1.0, None

        # Layer 1: Pixel Difference
        frame_diff = cv2.absdiff(self.prev_frame_gray, gray)
        _, thresh = cv2.threshold(
            frame_diff, config.INTENSITY_THRESHOLD, 255, cv2.THRESH_BINARY
        )
        diff_score = np.count_nonzero(thresh) / gray.size

        # Layer 2: SSIM
        ssim_score = 1.0
        ssim_drop = 0.0
        if HAS_SKIMAGE:
            curr_small = self._get_small(gray)
            ssim_score = skimage_ssim(self.prev_frame_small, curr_small)
            ssim_drop = 1.0 - ssim_score
            self.prev_frame_small = curr_small
        else:
            ssim_drop = diff_score

        is_candidate = (
            diff_score > config.PIXEL_DIFF_THRESHOLD and
            ssim_drop > config.SSIM_DROP_THRESHOLD
        )

        if is_candidate:
            logger.debug(f"Candidate frame detected: diff={diff_score:.4f}, ssim_drop={ssim_drop:.4f}")

        self.prev_frame_gray = gray
        return is_candidate, diff_score, ssim_score, thresh

    def _get_small(self, gray):
        h, w = gray.shape
        new_w = config.SSIM_RESIZE_WIDTH
        new_h = int(h * new_w / w)
        return cv2.resize(gray, (new_w, new_h), interpolation=cv2.INTER_AREA)

    def reset(self):
        self.prev_frame_gray = None
        self.prev_frame_small = None
