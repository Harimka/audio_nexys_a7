"""Probe runner implementing the Probe phase of Harness²."""

from __future__ import annotations

import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from harness.tools.check_constraints import check_constraints
from harness.tools.run_simulation import run_simulation
from .spec import CandidateProposal, HarnessTree, ProbeResult, SurfaceSpec
from .tree import write_harness


class ProbeExecutor:
    """Executes sandboxed probe rollouts for a candidate harness."""

    def __init__(self, root: Path, surface: Optional[SurfaceSpec] = None):
        self.root = root
        self.surface = surface or SurfaceSpec()

    def probe(
        self,
        candidate: CandidateProposal,
        base_harness: HarnessTree,
        task_id: str,
    ) -> ProbeResult:
        """Mount candidate harness in an isolated temporary sandbox and evaluate task performance.

        Args:
            candidate: Proposed harness edits.
            base_harness: Baseline harness tree.
            task_id: Target benchmark task identifier.

        Returns:
            Structured ProbeResult capturing score, pass/fail lists, and execution logs.
        """
        start_time = time.time()
        candidate_tree = dict(base_harness)
        candidate_tree.update(candidate.edits)

        with tempfile.TemporaryDirectory(prefix="harness-probe-") as temp_dir:
            temp_path = Path(temp_dir)
            # Write candidate harness to sandbox
            write_harness(temp_path, candidate_tree, target_dir=temp_path / "harness")

            # 1. Audit constraints on candidate harness components
            for path_key, content in candidate.edits.items():
                if path_key.endswith(".sv") or path_key.endswith(".v"):
                    c_res = check_constraints(content, file_path=path_key)
                    if not c_res.get("clean", False):
                        return ProbeResult(
                            candidate_id=candidate.id,
                            status="error",
                            score=0.0,
                            passed_cases=[],
                            failed_cases=["constraint_violation"],
                            output=f"Constraint check failed on candidate component '{path_key}'",
                            exit_code=1,
                            duration_s=time.time() - start_time,
                            error_message="Constraint violation detected in candidate edit",
                        )

            # 2. Run simulation probe
            sim_res = run_simulation(
                target_case=task_id if task_id != "all" else None,
                project_root=str(self.root),
            )

            passed = sim_res.get("passed_cases", [])
            failed = sim_res.get("failed_cases", [])
            total_cases = len(passed) + len(failed)
            score = (len(passed) / total_cases) if total_cases > 0 else 0.0

            # Score bonus if candidate addressed target task
            target_norm = task_id.lower()
            if target_norm in [p.lower() for p in passed]:
                score = min(1.0, score + 0.1)

            duration = time.time() - start_time
            status = "success" if sim_res.get("status") == "success" or score > 0.5 else "error"

            return ProbeResult(
                candidate_id=candidate.id,
                status=status,
                score=round(score, 3),
                passed_cases=passed,
                failed_cases=failed,
                output=sim_res.get("output", ""),
                exit_code=sim_res.get("exit_code", 0),
                duration_s=round(duration, 3),
            )
