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
    import sys
    import platform

    # Instant check for macOS (Apple Silicon vs Intel)
    if sys.platform == "darwin":
        if platform.machine() in ("arm64", "aarch64"):
            return "mps", "Apple Silicon Unified Memory (Metal Performance Shaders / MPS)"
        return "cpu", "Intel Mac Multi-Threaded CPU"

    try:
        import torch

        # Windows / Linux: check for NVIDIA CUDA GPU acceleration
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            vram_gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            return "cuda", f"NVIDIA CUDA: {gpu_name} ({vram_gb:.1f} GB VRAM)"

    except Exception:
        pass

    return "cpu", "Multi-Threaded CPU Fallback"
