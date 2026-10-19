"""
utils.hardware_check — Accelerator & Compute Device Detection
=============================================================
Detects available acceleration devices for NVIDIA LocateAnything-3B & Voxtral 4B:
  - Apple Silicon GPU (Metal Performance Shaders / MPS)
  - NVIDIA CUDA GPU
  - High-concurrency Multi-Threaded CPU
"""

from __future__ import annotations

import logging
from typing import Tuple

logger = logging.getLogger("deskmate.hardware")


def get_inference_device() -> Tuple[str, str]:
    """
    Returns (device_str, description)
    Options: 'mps' (Apple Silicon), 'cuda' (NVIDIA GPU), 'cpu' (Processor)
    """
    try:
        import torch

        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            vram_gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            return "cuda", f"NVIDIA CUDA: {gpu_name} ({vram_gb:.1f} GB VRAM)"

        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps", "Apple Silicon Unified Memory (Metal Performance Shaders / MPS)"

    except ImportError:
        pass

    return "cpu", "Multi-Threaded CPU Fallback"


def log_hardware_status() -> str:
    """Logs the detected hardware accelerator status."""
    device, desc = get_inference_device()
    if device in ("cuda", "mps"):
        logger.info(f"Hardware Acceleration ACTIVE: Using {desc} [device='{device}']")
    else:
        logger.info(f"Hardware Acceleration: Running on CPU [device='{device}']")
    return device
