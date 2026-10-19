"""
services.common.telemetry — Shared Telemetry & Metric Tracking
=============================================================
Provides clean timing, token usage tracking, and execution metrics.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass
class ExecutionTelemetry:
    """Tracks latency, resource usage, and token throughput."""
    service_name: str
    start_time: float = field(default_factory=time.time)
    end_time: Optional[float] = None
    input_tokens: int = 0
    output_tokens: int = 0
    extra_metrics: Dict[str, Any] = field(default_factory=dict)

    def stop(self) -> float:
        """Stop timer and return total elapsed duration in seconds."""
        self.end_time = time.time()
        return self.duration

    @property
    def duration(self) -> float:
        if self.end_time is not None:
            return round(self.end_time - self.start_time, 3)
        return round(time.time() - self.start_time, 3)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "service": self.service_name,
            "duration_seconds": self.duration,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "total_tokens": self.input_tokens + self.output_tokens,
            "metrics": self.extra_metrics,
        }
