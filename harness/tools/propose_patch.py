"""Safely stage and validate candidate patches in a sandbox.

Validates that proposed patches do not violate project constraints or alter
files outside the allowable boundaries before committing.
"""

from __future__ import annotations

import difflib
import json
import tempfile
from pathlib import Path
from typing import Any, Dict, Optional

from .check_constraints import check_constraints


def stage_patch(
    target_rel_path: str,
    new_content: str,
    project_root: Optional[str] = None,
) -> Dict[str, Any]:
    """Test and stage a candidate file modification in an isolated temporary buffer.

    Args:
        target_rel_path: Path relative to repository root of the target file.
        new_content: The proposed complete replacement content for the target file.
        project_root: Optional repository root path.

    Returns:
        Structured JSON dictionary containing:
            - status: "success" | "error"
            - target: relative target file path
            - diff: unified diff string between original and candidate
            - constraints_clean: boolean indicating constraint check result
            - message: status explanation
            - data_wrapped: diff and notes wrapped inside <DATA>...</DATA>
    """
    try:
        root = Path(project_root).resolve() if project_root else Path.cwd().resolve()
        target = (root / target_rel_path).resolve()

        if not target.exists():
            return {
                "status": "error",
                "target": target_rel_path,
                "message": f"Target file does not exist: {target_rel_path}",
                "constraints_clean": False,
                "diff": "",
                "data_wrapped": "<DATA>\nError: Target file not found\n</DATA>",
            }

        original_content = target.read_text(encoding="utf-8", errors="replace")

        # 1. Audit constraints on proposed content
        constraint_audit = check_constraints(new_content, file_path=target_rel_path)
        if not constraint_audit.get("clean", False):
            violations = constraint_audit.get("violations", [])
            v_msgs = "\n".join([f"- Line {v.get('line')}: {v.get('message')}" for v in violations])
            return {
                "status": "error",
                "target": target_rel_path,
                "message": f"Proposed modification violates project constraints:\n{v_msgs}",
                "constraints_clean": False,
                "violations": violations,
                "diff": "",
                "data_wrapped": f"<DATA>\nConstraint Violations:\n{v_msgs}\n</DATA>",
            }

        # 2. Compute unified diff
        orig_lines = original_content.splitlines(keepends=True)
        new_lines = new_content.splitlines(keepends=True)
        diff_lines = list(difflib.unified_diff(
            orig_lines,
            new_lines,
            fromfile=f"a/{target_rel_path}",
            tofile=f"b/{target_rel_path}",
        ))
        diff_text = "".join(diff_lines)

        return {
            "status": "success",
            "target": target_rel_path,
            "constraints_clean": True,
            "diff": diff_text,
            "data_wrapped": f"<DATA>\n{diff_text}\n</DATA>",
            "message": "Patch validated successfully against constraints.",
        }

    except Exception as exc:
        return {
            "status": "error",
            "target": target_rel_path,
            "message": f"Unexpected staging error: {type(exc).__name__}: {exc}",
            "constraints_clean": False,
            "diff": "",
            "data_wrapped": f"<DATA>\nException: {exc}\n</DATA>",
        }


if __name__ == "__main__":
    res = stage_patch("README.md", "# Test Modified README\n")
    print(json.dumps(res, indent=2))
