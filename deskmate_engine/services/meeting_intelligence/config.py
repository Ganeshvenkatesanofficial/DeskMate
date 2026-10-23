"""
services.meeting_intelligence.config — Computer Vision Detection Parameters
=============================================================================
Centralized operational thresholds, safety masks, ROI sizing, and temporal
tracking parameters for the 8-stage meeting event detection pipeline.
"""

# Spatial Awareness & Safety Mask Margins (fraction of screen; 0 = capture edge to edge)
IGNORE_TOP_PCT = 0.0          # Edge-to-edge capture without clipping titlebars/tabs
IGNORE_BOTTOM_PCT = 0.0       # Edge-to-edge capture without clipping dock/taskbars
IGNORE_LEFT_PCT = 0.0          # Left edge margin
IGNORE_RIGHT_PCT_MIN = 0.0     # Default right edge margin
IGNORE_RIGHT_PCT_MAX = 0.0     # Edge-to-edge capture without clipping sidebars/slides

# Change Detection & Frame Differencing
INTENSITY_THRESHOLD = 15       # Gray difference threshold for candidate pixels (detects subtle typing/UI state)
PIXEL_DIFF_THRESHOLD = 0.005   # Fraction of changed pixels to trigger candidate
SSIM_DROP_THRESHOLD = 0.005    # Structural similarity drop sensitivity
SSIM_RESIZE_WIDTH = 320        # Resolution for high-speed SSIM computation
MIN_VISUAL_DIFF_SSIM = 0.94    # Balanced visual dedup (0.94 skips very similar frames)

# Action-Centric ROI Extraction (16:9 widescreen format)
ROI_SIZE = (640, 360)          # Base ROI dimensions (w, h) in 16:9 ratio
ROI_ADAPTIVE_EXPAND = 1.2      # Expansion factor around active motion clusters
ROI_ASPECT_RATIO = 16 / 9
ROI_MIN_SIZE = (320, 180)      # Smallest crop (w, h)

# Cursor Tracking & Click Detection
CURSOR_SMOOTHING_WINDOW = 5
CURSOR_SCALES = [0.8, 1.0, 1.25]
CURSOR_MATCH_THRESHOLD = 0.60
CURSOR_TEMPLATES_DIR = "assets/cursor_templates"
STABLE_CURSOR_MAX_MOVE = 20    # Max pixel movement for stable cursor (high-res tolerance)
CLICK_WINDOW_FRAMES = 3        # Number of frames stable cursor precedes click
EVENT_COOLDOWN_MS = 2000       # Minimum cooldown between consecutive interaction events to prevent duplicates

# Live pipeline timing
STARTUP_GRACE_SECONDS = 1.5    # Ignore the click on DeskMate's own Start button
MILESTONE_INTERVAL_SECONDS = 40.0  # Force a screenshot checkpoint this often during long static views
DEDUP_THUMBNAIL_SIZE = (320, 180)  # Grayscale size used for SSIM dedup

# Temporal Tracking
TRACKER_IOU_THRESHOLD = 0.30
TRACKER_MAX_DISAPPEARED = 8

# Video Sampling & Pipeline Defaults
SAMPLE_FPS = 2.0
IGNORE_REGIONS = []
VIDEO_EXTENSIONS = [".mp4", ".mov", ".mkv", ".avi", ".webm"]
OUTPUT_DIR = "output/sessions"
EVENT_ASSETS_DIR = "output/sessions/assets"
