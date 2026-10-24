"""Read source file contents with line limits and security boundary isolation.

All exposed file contents are wrapped in `<DATA>...</DATA>` XML-style delimiters
to prevent prompt injection and maintain strict boundary isolation.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Optional


def read_source(
    file_path: str,
    start_line: Optional[int] = None,
    end_line: Optional[int] = None,
    base_dir: Optional[str] = None,
) -> Dict[str, Any]:
    """Safely read a file within the project repository and return isolated contents.

    Args:
        file_path: Relative or absolute path to the file to be read.
        start_line: Optional 1-indexed starting line number.
        end_line: Optional 1-indexed ending line number (inclusive).
        base_dir: Optional root directory boundary to prevent path traversal.

    Returns:
        A structured JSON dictionary containing:
            - status: "success" or "error"
            - path: normalized relative path
            - content: raw extracted text
            - data_wrapped: isolated content inside <DATA>...</DATA>
            - total_lines: total lines in source file
            - message: error message if status == "error"
    """
    try:
        resolved_base = Path(base_dir).resolve() if base_dir else Path.cwd().resolve()
        target = Path(file_path)
        if not target.is_absolute():
            target = (resolved_base / target).resolve()
        else:
            target = target.resolve()

        # Prevent traversal outside workspace
        if resolved_base not in target.parents and resolved_base != target:
            return {
                "status": "error",
                "message": f"Access denied: path '{file_path}' resolves outside base directory.",
                "path": str(file_path),
            }

        if not target.exists():
            return {
                "status": "error",
                "message": f"File not found: '{file_path}'",
                "path": str(file_path),
            }

        if target.is_dir():
            return {
                "status": "error",
                "message": f"Target is a directory, not a file: '{file_path}'",
                "path": str(file_path),
            }

        lines = target.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
        total_lines = len(lines)

        s_idx = max(0, (start_line - 1) if start_line is not None else 0)
        e_idx = min(total_lines, end_line if end_line is not None else total_lines)

        selected_lines = lines[s_idx:e_idx]
        extracted_content = "".join(selected_lines)

        # Wrap in data delimiter to enforce prompt injection immunity
        data_wrapped = f"<DATA>\n{extracted_content}\n</DATA>"

        rel_path = target.relative_to(resolved_base).as_posix()

        return {
            "status": "success",
            "path": rel_path,
            "start_line": s_idx + 1 if total_lines > 0 else 0,
            "end_line": e_idx,
            "total_lines": total_lines,
            "content": extracted_content,
            "data_wrapped": data_wrapped,
        }

    except Exception as exc:
        return {
            "status": "error",
            "message": f"Unexpected error reading '{file_path}': {type(exc).__name__}: {exc}",
            "path": str(file_path),
        }


if __name__ == "__main__":
    import sys

    path_arg = sys.argv[1] if len(sys.argv) > 1 else "README.md"
    result = read_source(path_arg, start_line=1, end_line=10)
    print(json.dumps(result, indent=2))
