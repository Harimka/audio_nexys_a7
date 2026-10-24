"""Trajectory evaluation task: Reset loss-of-lock defect."""

from __future__ import annotations

from typing import Any, Dict

TASK_SPEC: Dict[str, Any] = {
    "task_id": "reset_loss_of_lock",
    "domain": "rtl_verification",
    "description": (
        "Diagnose and correct the reset button debouncer (reset_button_debouncer.sv) "
        "such that rst_n asserts to 0 whenever PLL lock is lost (locked == 0)."
    ),
    "target_file": "src/rtl/reset_button_debouncer.sv",
    "expected_behavior": "rst_n <= 1'b0 when locked == 1'b0",
    "baseline_observation": "REPRODUCED RESET ISSUE: rst_n remains 1 after PLL lock is lost",
    "evaluation_criteria": [
        "rst_n drops to 0 synchronously when locked de-asserts",
        "Debounce timing remains stable after lock re-assertion",
        "Constraint check clean (no prohibited IP, no active high AUD_PWM)",
    ],
}
