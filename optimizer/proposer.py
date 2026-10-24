"""Candidate proposer implementing the Propose phase of Harness²."""

from __future__ import annotations

import os
from abc import ABC, abstractmethod
from typing import Dict, List, Optional

from .spec import CandidateProposal, HarnessTree, SurfaceSpec
from .tree import diff_trees


class BaseProposer(ABC):
    """Abstract interface for proposing candidate modifications to a harness."""

    @abstractmethod
    def propose(
        self,
        iteration: int,
        active_harness: HarnessTree,
        task_id: str,
        recent_probe_feedback: Optional[str] = None,
    ) -> CandidateProposal:
        """Generate a candidate modification to the active harness tree."""
        pass


class DeterministicProposer(BaseProposer):
    """Deterministic, reproducible proposer for automated local testing and zero-credential CI.

    Applies structured 4-D refinement patterns to harness components based on failure feedback.
    """

    def __init__(self, surface: Optional[SurfaceSpec] = None):
        self.surface = surface or SurfaceSpec()

    def propose(
        self,
        iteration: int,
        active_harness: HarnessTree,
        task_id: str,
        recent_probe_feedback: Optional[str] = None,
    ) -> CandidateProposal:
        candidate_id = f"cand-{task_id}-iter{iteration}"
        edits: Dict[str, str] = {}
        rationale = ""

        if "reset" in task_id.lower() or (recent_probe_feedback and "reset" in recent_probe_feedback.lower()):
            rationale = "Tighten reset recovery rule in systemprompt and guardrails to handle PLL loss-of-lock."
            orig_prompt = active_harness.get("systemprompt.md", "")
            additional_rule = (
                "\n\n### MANDATORY RESET RECOVERY RULE (Iterative Refinement)\n"
                "- When synthesizing or verifying reset logic (e.g., in reset_button_debouncer.sv), "
                "always tie active-low reset assertion (rst_n = 0) directly and synchronously to PLL lock loss (!locked).\n"
            )
            if "MANDATORY RESET RECOVERY RULE" not in orig_prompt:
                edits["systemprompt.md"] = orig_prompt + additional_rule

            orig_guard = active_harness.get("guardrails.md", "")
            guard_addition = (
                "\n\n## Reset Handling Invariant\n"
                "- Never allow rst_n to float high or remain 1'b1 when locked is 1'b0.\n"
            )
            if "Reset Handling Invariant" not in orig_guard:
                edits["guardrails.md"] = orig_guard + guard_addition

        elif "vga" in task_id.lower() or (recent_probe_feedback and "vga" in recent_probe_feedback.lower()):
            rationale = "Clarify 800x600 @ 72Hz vertical front porch timing invariants."
            orig_prompt = active_harness.get("systemprompt.md", "")
            additional_rule = (
                "\n\n### MANDATORY VGA TIMING RULE\n"
                "- Vertical sync front porch for 800x600 @ 72Hz is exactly 37 lines. Total vertical frame lines = 666.\n"
            )
            if "MANDATORY VGA TIMING RULE" not in orig_prompt:
                edits["systemprompt.md"] = orig_prompt + additional_rule

        else:
            rationale = "General instruction refinement: strict schema adherence and prompt isolation enforcement."
            orig_prompt = active_harness.get("systemprompt.md", "")
            additional_rule = (
                "\n\n### CONTRACT ENFORCEMENT\n"
                "- Every generated tool argument must be valid JSON enclosed in <DATA>...</DATA> blocks.\n"
            )
            if "CONTRACT ENFORCEMENT" not in orig_prompt:
                edits["systemprompt.md"] = orig_prompt + additional_rule

        # If no edits generated, make a no-op candidate
        if not edits:
            edits["systemprompt.md"] = active_harness.get("systemprompt.md", "") + "\n<!-- candidate evaluated -->\n"
            rationale = "No-op stability probe."

        # Compute diffs against active harness
        new_tree = dict(active_harness)
        new_tree.update(edits)
        diffs = diff_trees(active_harness, new_tree)

        return CandidateProposal(
            id=candidate_id,
            rationale=rationale,
            edits=edits,
            diffs=diffs,
        )


def get_proposer(mode: str = "deterministic") -> BaseProposer:
    """Factory helper to obtain a proposer instance."""
    if mode == "deterministic":
        return DeterministicProposer()
    raise ValueError(f"Unsupported proposer mode '{mode}'. Use 'deterministic'.")
