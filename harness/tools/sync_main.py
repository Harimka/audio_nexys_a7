"""Safe synchronization and conflict analysis tool between main and harness branch.

Checks divergence between current branch and main, analyzes file collision
boundaries, and ensures zero unexpected regressions.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional


def analyze_main_divergence(
    base_branch: str = "main",
    project_root: Optional[str] = None,
) -> Dict[str, Any]:
    """Analyze changes between current working branch and main before merging.

    Args:
        base_branch: Name of base branch to compare against (default: 'main').
        project_root: Root of the repository.

    Returns:
        Structured JSON dictionary with:
            - status: "success" | "error"
            - current_branch: active branch name
            - base_branch: target comparison branch
            - can_fast_forward: boolean
            - modified_in_main: list of files modified on main
            - modified_in_current: list of files modified locally
            - colliding_files: list of conflicting/intersecting files
            - recommendations: action steps for the engineer/agent
    """
    root = Path(project_root).resolve() if project_root else Path.cwd().resolve()

    try:
        # 1. Get current branch
        curr_proc = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=True,
        )
        current_branch = curr_proc.stdout.strip()

        # 2. Check if base_branch exists
        has_base = subprocess.run(
            ["git", "rev-parse", "--verify", base_branch],
            cwd=str(root),
            capture_output=True,
            text=True,
        )
        if has_base.returncode != 0:
            return {
                "status": "error",
                "message": f"Base branch '{base_branch}' not found in local git repository.",
                "current_branch": current_branch,
            }

        # 3. Find merge base
        mb_proc = subprocess.run(
            ["git", "merge-base", current_branch, base_branch],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=True,
        )
        merge_base = mb_proc.stdout.strip()

        # 4. Files modified in main since merge-base
        diff_main_proc = subprocess.run(
            ["git", "diff", "--name-only", merge_base, base_branch],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=True,
        )
        files_in_main = [f.strip() for f in diff_main_proc.stdout.splitlines() if f.strip()]

        # 5. Files modified in current branch since merge-base
        diff_curr_proc = subprocess.run(
            ["git", "diff", "--name-only", merge_base, current_branch],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=True,
        )
        files_in_curr = [f.strip() for f in diff_curr_proc.stdout.splitlines() if f.strip()]

        # Untracked or staged working tree changes
        status_proc = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=True,
        )
        working_tree_files = []
        for line in status_proc.stdout.splitlines():
            if len(line) > 3:
                working_tree_files.append(line[3:].strip())

        all_current_touched = set(files_in_curr) | set(working_tree_files)
        collisions = sorted(list(set(files_in_main) & all_current_touched))

        safe_to_sync = len(collisions) == 0

        recommendations: List[str] = []
        if safe_to_sync:
            if not files_in_main:
                recommendations.append("Branch is fully aligned with main; no new changes in main.")
            else:
                recommendations.append("No file collisions detected. Changes from main can be safely merged or rebased.")
        else:
            recommendations.append(
                f"POTENTIAL CONFLICT DETECTED in files: {', '.join(collisions)}. "
                "Resolve differences manually with file owners before merging."
            )

        return {
            "status": "success",
            "current_branch": current_branch,
            "base_branch": base_branch,
            "merge_base": merge_base,
            "files_modified_in_main": files_in_main,
            "files_modified_in_current": sorted(list(all_current_touched)),
            "colliding_files": collisions,
            "safe_to_sync": safe_to_sync,
            "recommendations": recommendations,
        }

    except Exception as exc:
        return {
            "status": "error",
            "message": f"Git divergence analysis failed: {type(exc).__name__}: {exc}",
        }


def pull_and_sync_main(project_root: Optional[str] = None) -> Dict[str, Any]:
    """Execute git fetch and safe merge of main into current branch if no collisions exist."""
    analysis = analyze_main_divergence(base_branch="main", project_root=project_root)
    if analysis.get("status") != "success":
        return analysis

    if not analysis.get("safe_to_sync", False):
        return {
            "status": "error",
            "message": "Aborting sync: collisions detected between main and current branch.",
            "collisions": analysis.get("colliding_files", []),
        }

    if not analysis.get("files_modified_in_main"):
        return {
            "status": "success",
            "message": "Already up to date with main. No merge needed.",
        }

    root = Path(project_root).resolve() if project_root else Path.cwd().resolve()
    try:
        proc = subprocess.run(
            ["git", "merge", "main", "--no-commit", "--no-ff"],
            cwd=str(root),
            capture_output=True,
            text=True,
        )
        return {
            "status": "success" if proc.returncode == 0 else "error",
            "exit_code": proc.returncode,
            "output": proc.stdout + ("\n" + proc.stderr if proc.stderr else ""),
            "message": "Main merged staged for verification." if proc.returncode == 0 else "Merge error occurred.",
        }
    except Exception as exc:
        return {
            "status": "error",
            "message": f"Execution failed: {exc}",
        }


if __name__ == "__main__":
    report = analyze_main_divergence()
    print(json.dumps(report, indent=2))
