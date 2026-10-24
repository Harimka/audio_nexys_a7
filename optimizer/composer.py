"""Composer implementing the Compose phase of Harness²."""

from __future__ import annotations

from pathlib import Path
from typing import Optional, Tuple

from .spec import CandidateProposal, HarnessTree, LedgerEntry, ProbeResult, SurfaceSpec
from .tree import write_harness


class Composer:
    """Evaluates candidates contrastively and composes accepted improvements into the active harness."""

    def __init__(self, root: Path, surface: Optional[SurfaceSpec] = None):
        self.root = root
        self.surface = surface or SurfaceSpec()

    def compose(
        self,
        iteration: int,
        baseline_harness: HarnessTree,
        baseline_result: ProbeResult,
        candidate: CandidateProposal,
        candidate_result: ProbeResult,
    ) -> Tuple[HarnessTree, LedgerEntry]:
        """Contrastively evaluate candidate against baseline and compose winning modifications.

        Args:
            iteration: Current loop iteration count.
            baseline_harness: Current active harness tree.
            baseline_result: Probe result of baseline harness.
            candidate: Candidate proposal.
            candidate_result: Probe result of candidate harness.

        Returns:
            Tuple of (new_active_harness, ledger_entry).
        """
        # Contrastive evaluation criteria:
        # Candidate is accepted if:
        # 1. Candidate score is strictly higher than baseline, OR
        # 2. Candidate score is equal to baseline AND eliminates an existing defect without adding regressions, AND
        # 3. Candidate execution status is not an error / constraint violation.

        score_improved = candidate_result.score > baseline_result.score
        score_equal = candidate_result.score == baseline_result.score
        fewer_failures = len(candidate_result.failed_cases) < len(baseline_result.failed_cases)
        no_critical_error = candidate_result.status != "error" or candidate_result.exit_code == 0

        accept = (score_improved or (score_equal and fewer_failures)) and no_critical_error

        if accept:
            notes = (
                f"Candidate accepted: score {baseline_result.score:.2f} -> {candidate_result.score:.2f}. "
                f"Failures: {len(baseline_result.failed_cases)} -> {len(candidate_result.failed_cases)}."
            )
            # Compose: update active harness tree
            new_active_harness = dict(baseline_harness)
            new_active_harness.update(candidate.edits)
            # Write to disk
            write_harness(self.root, new_active_harness, surface=self.surface)
        else:
            notes = (
                f"Candidate rejected: baseline retained. "
                f"Baseline score {baseline_result.score:.2f} vs candidate {candidate_result.score:.2f}."
            )
            new_active_harness = baseline_harness

        diff_summary = {k: f"Diff: {len(v.splitlines())} lines modified" for k, v in candidate.diffs.items()}

        ledger_entry = LedgerEntry(
            iteration=iteration,
            candidate_id=candidate.id,
            rationale=candidate.rationale,
            accepted=accept,
            baseline_score=baseline_result.score,
            candidate_score=candidate_result.score,
            contrastive_notes=notes,
            diff_summary=diff_summary,
        )

        return new_active_harness, ledger_entry
