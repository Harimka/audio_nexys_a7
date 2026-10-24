"""Harness tree manager: read, write, snapshot, and compute diffs."""

from __future__ import annotations

import difflib
from pathlib import Path
from typing import Dict, Optional, Tuple

from .spec import HarnessTree, SurfaceSpec


def read_harness(root: Path, surface: Optional[SurfaceSpec] = None) -> HarnessTree:
    """Read the active harness tree from disk.

    Args:
        root: Workspace root directory.
        surface: Surface specification.

    Returns:
        Mapping of relative path inside harness directory to file content.
    """
    surface = surface or SurfaceSpec()
    harness_base = root / surface.harness_dir
    tree: HarnessTree = {}

    if not harness_base.exists():
        return tree

    for path in harness_base.rglob("*"):
        if path.is_file():
            # Exclude python cache files
            if "__pycache__" in path.parts or path.suffix == ".pyc":
                continue
            rel = path.relative_to(harness_base).as_posix()
            try:
                tree[rel] = path.read_text(encoding="utf-8", errors="replace")
            except Exception:
                pass

    return tree


def write_harness(
    root: Path,
    tree: HarnessTree,
    target_dir: Optional[Path] = None,
    surface: Optional[SurfaceSpec] = None,
) -> Path:
    """Write a harness tree to disk (either active harness or sandbox).

    Args:
        root: Workspace root.
        tree: Mapping of relative path to file content.
        target_dir: Specific destination directory, defaults to harness_dir.
        surface: Surface specification.

    Returns:
        The written directory Path.
    """
    surface = surface or SurfaceSpec()
    dest = target_dir if target_dir is not None else (root / surface.harness_dir)
    dest.mkdir(parents=True, exist_ok=True)

    for rel_path, content in tree.items():
        file_path = dest / rel_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content, encoding="utf-8")

    return dest


def diff_trees(base: HarnessTree, candidate: HarnessTree) -> Dict[str, str]:
    """Compute unified diffs for all modified, added, or deleted components.

    Args:
        base: Baseline harness tree.
        candidate: Candidate harness tree.

    Returns:
        Dictionary mapping file path to unified diff string.
    """
    diffs: Dict[str, str] = {}
    all_keys = sorted(set(base.keys()) | set(candidate.keys()))

    for key in all_keys:
        old_text = base.get(key, "")
        new_text = candidate.get(key, "")
        if old_text != new_text:
            orig_lines = old_text.splitlines(keepends=True)
            new_lines = new_text.splitlines(keepends=True)
            delta = "".join(difflib.unified_diff(
                orig_lines,
                new_lines,
                fromfile=f"a/{key}",
                tofile=f"b/{key}",
            ))
            diffs[key] = delta

    return diffs
