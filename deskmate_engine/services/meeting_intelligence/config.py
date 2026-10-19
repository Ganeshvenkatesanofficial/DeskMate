"""
services.meeting_intelligence.config — Computer Vision Detection Parameters
=============================================================================
Centralized operational thresholds, safety masks, ROI sizing, and temporal
tracking parameters for the 8-stage meeting event detection pipeline.
"""

# Spatial Awareness & Safety Mask Margins (fraction of screen dimension)
IGNORE_TOP_PCT = 0.04          # OS Titlebar / Menu bar
IGNORE_BOTTOM_PCT = 0.05       # macOS Dock / Windows Taskbar
IGNORE_LEFT_PCT = 0.0          # Left edge margin
IGNORE_RIGHT_PCT_MIN = 0.0     # Default right edge margin
IGNORE_RIGHT_PCT_MAX = 0.25    # Right sidebar (video tiles / chat pane)

# Change Detection & Frame Differencing
INTENSITY_THRESHOLD = 30       # Gray difference threshold for candidate pixels
PIXEL_DIFF_THRESHOLD = 0.003   # Fraction of changed pixels to trigger candidate
SSIM_DROP_THRESHOLD = 0.015    # Drop in structural similarity
SSIM_RESIZE_WIDTH = 320        # Resolution for high-speed SSIM computation
MIN_VISUAL_DIFF_SSIM = 0.985   # Dedup threshold

# Action-Centric ROI Extraction
ROI_SIZE = (640, 640)          # Base ROI dimensions (w, h)
ROI_OVERLAY_MIN_PCT = 0.0008   # Discard ROIs smaller than 0.08% of screen
ROI_ADAPTIVE_EXPAND = 1.25     # Expansion factor around active motion clusters

# Cursor Tracking & Click Detection
CURSOR_SMOOTHING_WINDOW = 5
CURSOR_SCALES = [0.8, 1.0, 1.25]
CURSOR_MATCH_THRESHOLD = 0.68
CURSOR_TEMPLATES_DIR = "assets/cursor_templates"
STABLE_CURSOR_MAX_MOVE = 18    # Max pixel movement for stable cursor
CLICK_WINDOW_FRAMES = 3        # Number of frames stable cursor precedes click
EVENT_COOLDOWN_MS = 800        # Minimum cooldown between consecutive interaction events

# Temporal Tracking
TRACKER_IOU_THRESHOLD = 0.30
TRACKER_MAX_DISAPPEARED = 8

# Video Sampling & Pipeline Defaults
SAMPLE_FPS = 2.0
IGNORE_REGIONS = []
VIDEO_EXTENSIONS = [".mp4", ".mov", ".mkv", ".avi", ".webm"]
OUTPUT_DIR = "output/sessions"
EVENT_ASSETS_DIR = "output/sessions/assets"
