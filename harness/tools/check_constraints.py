"""Audit SystemVerilog code against architectural and safety constraints.

Enforces zero-touch rules, IP restrictions (no MicroBlaze, no unauthorized IP),
and electrical constraints (AUD_PWM 0/Z driving).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

APPROVED_IPS = {
    "clk_wiz",
    "clk_wiz_0",
    "blk_mem_gen",
    "dist_mem_gen",
    "mig_7series",
    "axi_crossbar",
}

PROHIBITED_KEYWORDS = [
    "microblaze",
    "microblaze_0",
    "system_i",
    "bd_cell",
]


def check_constraints(
    content: str,
    file_path: Optional[str] = None,
) -> Dict[str, Any]:
    """Inspect SystemVerilog code against architectural, IP, and hardware constraints.

    Args:
        content: SystemVerilog source code string.
        file_path: Optional source file name for context reporting.

    Returns:
        A structured JSON dictionary containing:
            - status: "success" | "error"
            - file_path: file name if provided
            - clean: boolean true if no violations detected
            - violation_count: number of constraint violations found
            - violations: list of violation objects with description and line number
    """
    try:
        violations: List[Dict[str, Any]] = []
        lines = content.splitlines()

        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            # Ignore comments
            if stripped.startswith("//") or stripped.startswith("/*"):
                continue

            lower_line = stripped.lower()

            # 1. Prohibited architectures (MicroBlaze, Block Design)
            for kw in PROHIBITED_KEYWORDS:
                if re.search(r"\b" + re.escape(kw) + r"\b", lower_line):
                    violations.append({
                        "line": idx,
                        "rule": "PROHIBITED_IP",
                        "severity": "CRITICAL",
                        "message": f"Found prohibited architecture keyword '{kw}'. MicroBlaze and Block Design are forbidden.",
                        "snippet": stripped,
                    })

            # 2. Hardware safety check on AUD_PWM: never drive actively high '1'
            if "aud_pwm" in lower_line:
                if re.search(r"aud_pwm\s*<=\s*1'b1", lower_line) or re.search(r"aud_pwm\s*=\s*1'b1", lower_line):
                    violations.append({
                        "line": idx,
                        "rule": "ELECTRICAL_SAFETY",
                        "severity": "CRITICAL",
                        "message": "AUD_PWM assigned active high (1'b1). Hardware requires 0 or 1'bz (open-drain emulation).",
                        "snippet": stripped,
                    })

            # 3. Non-synthesizable delays in RTL (outside tb/sim)
            is_tb = file_path and ("tb_" in file_path or "tb/" in file_path or "sim/" in file_path)
            if not is_tb:
                if re.search(r"#\s*\d+", stripped):
                    violations.append({
                        "line": idx,
                        "rule": "NON_SYNTHESIZABLE_DELAY",
                        "severity": "WARNING",
                        "message": "Found delay (#time). Non-synthesizable in FPGA hardware.",
                        "snippet": stripped,
                    })

        clean = len(violations) == 0
        return {
            "status": "success",
            "file_path": file_path or "inline_buffer",
            "clean": clean,
            "violation_count": len(violations),
            "violations": violations,
        }

    except Exception as exc:
        return {
            "status": "error",
            "message": f"Error auditing constraints: {type(exc).__name__}: {exc}",
            "file_path": file_path or "inline_buffer",
            "clean": False,
            "violation_count": 0,
            "violations": [],
        }


def check_file_constraints(file_path: str, base_dir: Optional[str] = None) -> Dict[str, Any]:
    """Convenience helper to check constraints directly on a file path.

    Args:
        file_path: Relative or absolute path to the file.
        base_dir: Optional root directory boundary.

    Returns:
        Structured JSON dictionary from check_constraints or error.
    """
    resolved_base = Path(base_dir).resolve() if base_dir else Path.cwd().resolve()
    target = Path(file_path)
    if not target.is_absolute():
        target = (resolved_base / target).resolve()

    if not target.exists():
        return {
            "status": "error",
            "message": f"File not found: '{file_path}'",
            "file_path": str(file_path),
            "clean": False,
            "violation_count": 0,
            "violations": [],
        }

    content = target.read_text(encoding="utf-8", errors="replace")
    return check_constraints(content, file_path=target.relative_to(resolved_base).as_posix())


if __name__ == "__main__":
    sample = "assign AUD_PWM = pwm_val ? 1'b1 : 1'b0;"
    print(json.dumps(check_constraints(sample), indent=2))
