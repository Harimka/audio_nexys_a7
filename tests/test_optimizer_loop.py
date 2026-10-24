"""Unit tests verifying the Harness² Propose -> Probe -> Compose optimization loop."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from optimizer.composer import Composer
from optimizer.loop import OptimizationLoop
from optimizer.probe import ProbeExecutor
from optimizer.proposer import DeterministicProposer
from optimizer.spec import CandidateProposal, SurfaceSpec
from optimizer.tree import diff_trees, read_harness, write_harness


class TestOptimizerLoop(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parent.parent

    def test_tree_read_and_diff(self) -> None:
        """Test reading active harness tree and computing diffs."""
        tree = read_harness(self.root)
        self.assertIn("systemprompt.md", tree)
        self.assertIn("guardrails.md", tree)
        self.assertIn("skills/prompt_engineering/SKILL.md", tree)

        candidate_tree = dict(tree)
        candidate_tree["systemprompt.md"] += "\n// Additional rule"
        diffs = diff_trees(tree, candidate_tree)
        self.assertIn("systemprompt.md", diffs)
        self.assertTrue(len(diffs["systemprompt.md"]) > 0)

    def test_deterministic_proposer(self) -> None:
        """Test deterministic proposer produces valid candidate proposals."""
        tree = read_harness(self.root)
        proposer = DeterministicProposer()
        proposal = proposer.propose(
            iteration=1,
            active_harness=tree,
            task_id="reset",
            recent_probe_feedback="REPRODUCED RESET DEFECT",
        )
        self.assertIsInstance(proposal, CandidateProposal)
        self.assertTrue(len(proposal.edits) > 0)
        self.assertIn("cand-reset-iter1", proposal.id)

    def test_end_to_end_loop_execution(self) -> None:
        """Test full Propose -> Probe -> Compose optimization loop in temporary sandbox."""
        with tempfile.TemporaryDirectory(prefix="test-opt-loop-") as temp_dir:
            temp_path = Path(temp_dir)
            ledger_file = temp_path / "ledger.jsonl"

            # Run 2 iterations
            loop = OptimizationLoop(
                root=self.root,
                ledger_path=ledger_file,
            )
            res = loop.run(task_id="reset", iterations=2)

            self.assertEqual(res["status"], "success")
            self.assertEqual(res["iterations_executed"], 2)
            self.assertIn("history", res)
            self.assertEqual(len(res["history"]), 2)
            self.assertTrue(ledger_file.exists())
            ledger_lines = ledger_file.read_text(encoding="utf-8").strip().splitlines()
            self.assertEqual(len(ledger_lines), 2)


if __name__ == "__main__":
    unittest.main()
