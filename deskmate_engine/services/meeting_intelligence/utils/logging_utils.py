"""
utils.logging_utils — Meeting Intelligence Structured Telemetry Logger
======================================================================
"""

import logging
import sys

_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)s | %(message)s"
_DATEFMT = "%H:%M:%S"


def setup_meeting_logger(name: str = "deskmate.meeting", level: int = logging.INFO) -> logging.Logger:
    """Configures structured console logging for meeting intelligence services."""
    logger = logging.getLogger(name)
    logger.setLevel(level)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter(_FORMAT, datefmt=_DATEFMT))
        logger.addHandler(handler)

    return logger
