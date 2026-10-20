import cv2
import numpy as np
import logging
from .. import config

logger = logging.getLogger(__name__)

def compute_ssim(img1: np.ndarray, img2: np.ndarray) -> float:
    """Fast, native OpenCV SSIM calculation without external scikit-image dependency."""
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    f1 = img1.astype(np.float64)
    f2 = img2.astype(np.float64)
    mu1 = cv2.GaussianBlur(f1, (11, 11), 1.5)
    mu2 = cv2.GaussianBlur(f2, (11, 11), 1.5)
    mu1_sq = mu1 ** 2
    mu2_sq = mu2 ** 2
    mu1_mu2 = mu1 * mu2
    sigma1_sq = cv2.GaussianBlur(f1 ** 2, (11, 11), 1.5) - mu1_sq
    sigma2_sq = cv2.GaussianBlur(f2 ** 2, (11, 11), 1.5) - mu2_sq
    sigma12 = cv2.GaussianBlur(f1 * f2, (11, 11), 1.5) - mu1_mu2
    ssim_map = ((2 * mu1_mu2 + c1) * (2 * sigma12 + c2)) / ((mu1_sq + mu2_sq + c1) * (sigma1_sq + sigma2_sq + c2))
    return float(ssim_map.mean())


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
        curr_small = self._get_small(gray)
        ssim_score = compute_ssim(self.prev_frame_small, curr_small)
        ssim_drop = 1.0 - ssim_score
        self.prev_frame_small = curr_small

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
