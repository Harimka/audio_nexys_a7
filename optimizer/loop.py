"""Recursive adaptation loop orchestrating Propose -> Probe -> Compose."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from .composer import Composer
from .probe import ProbeExecutor
from .proposer import BaseProposer, DeterministicProposer
from .spec import HarnessTree, LedgerEntry, ProbeResult, SurfaceSpec
from .tree import read_harness


class OptimizationLoop:
    """Orchestrates recursive Propose -> Probe -> Compose cycles."""

    def __init__(
        self,
        root: Optional[Path] = None,
        surface: Optional[SurfaceSpec] = None,
        proposer: Optional[BaseProposer] = None,
        ledger_path: Optional[Path] = None,
    ):
        self.root = root or Path.cwd().resolve()
        self.surface = surface or SurfaceSpec()
        self.proposer = proposer or DeterministicProposer(self.surface)
        self.probe_executor = ProbeExecutor(self.root, self.surface)
        self.composer = Composer(self.root, self.surface)
        self.ledger_path = ledger_path or (self.root / "optimizer" / "ledger.jsonl")

    def run(
        self,
        task_id: str = "reset",
        iterations: int = 2,
    ) -> Dict[str, Any]:
        """Execute K iterations of recursive harness adaptation.

        Args:
            task_id: The target task or defect benchmark identifier.
            iterations: Number of adaptation cycles to execute.

        Returns:
            Dictionary containing optimization summary, final score, and iteration history.
        """
        active_harness = read_harness(self.root, self.surface)

        # Baseline probe run
        from .spec import CandidateProposal
        baseline_pseudo_candidate = CandidateProposal(
            id="baseline-initial",
            rationale="Initial baseline measurement",
            edits={},
        )
        baseline_result = self.probe_executor.probe(
            baseline_pseudo_candidate,
            active_harness,
            task_id,
        )

        history: List[LedgerEntry] = []
        recent_feedback = baseline_result.output

        for iter_idx in range(1, iterations + 1):
            # 1. PROPOSE
            candidate = self.proposer.propose(
                iteration=iter_idx,
                active_harness=active_harness,
                task_id=task_id,
                recent_probe_feedback=recent_feedback,
            )

            # 2. PROBE
            candidate_result = self.probe_executor.probe(
                candidate,
                active_harness,
                task_id,
            )

            # 3. COMPOSE
            active_harness, entry = self.composer.compose(
                iteration=iter_idx,
                baseline_harness=active_harness,
                baseline_result=baseline_result,
                candidate=candidate,
                candidate_result=candidate_result,
            )

            history.append(entry)
            self._append_to_ledger(entry)

            # Update baseline for next iteration if candidate accepted
            if entry.accepted:
                baseline_result = candidate_result

            recent_feedback = candidate_result.output

        return {
            "status": "success",
            "task_id": task_id,
            "iterations_executed": iterations,
            "initial_score": history[0].baseline_score if history else 0.0,
            "final_score": baseline_result.score,
            "accepted_count": sum(1 for e in history if e.accepted),
            "history": [e.to_dict() for e in history],
        }

    def _append_to_ledger(self, entry: LedgerEntry) -> None:
        """Append an immutable iteration record to the ledger JSONL file."""
        self.ledger_path.parent.mkdir(parents=True, exist_ok=True)
        with self.ledger_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry.to_dict()) + "\n")
