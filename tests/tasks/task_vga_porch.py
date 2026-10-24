"""Trajectory evaluation task: VGA vertical front porch alignment."""

from __future__ import annotations

from typing import Any, Dict

TASK_SPEC: Dict[str, Any] = {
    "task_id": "vga_vs_front_porch",
    "domain": "rtl_verification",
    "description": (
        "Diagnose and correct the VGA display controller (display_ctrl.sv) "
        "to align the Vertical Sync (VS) transition accurately with the configured 800x600 @ 72Hz timing."
    ),
    "target_file": "src/rtl/display_ctrl.sv",
    "baseline_observation": "REPRODUCED VGA ISSUE: VS differs from configured front porch by 2110 pixel clocks/frame",
    "evaluation_criteria": [
        "Vertical front porch matches exact standard specification",
        "Horizontal active, sync, and porch timings unchanged",
        "Constraint check clean",
    ],
}
