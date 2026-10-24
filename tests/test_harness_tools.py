"""Unit tests verifying Harness tool contracts and security boundaries."""

from __future__ import annotations

import unittest
from pathlib import Path

from harness.tools.check_constraints import check_constraints
from harness.tools.propose_patch import stage_patch
from harness.tools.read_source import read_source
from harness.tools.run_simulation import run_simulation
from harness.tools.sync_main import analyze_main_divergence


class TestHarnessTools(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parent.parent

    def test_read_source_contract_and_boundary(self) -> None:
        """Test read_source returns structured JSON with <DATA> wrapping."""
        res = read_source("README.md", start_line=1, end_line=5, base_dir=str(self.root))
        self.assertIn("status", res)
        self.assertEqual(res["status"], "success")
        self.assertIn("data_wrapped", res)
        self.assertTrue(res["data_wrapped"].startswith("<DATA>"))
        self.assertTrue(res["data_wrapped"].endswith("</DATA>"))
        self.assertIn("content", res)
        self.assertIn("path", res)

    def test_read_source_boundary_violation(self) -> None:
        """Test read_source rejects directory traversal outside workspace."""
        res = read_source("../../some_secret_file.txt", base_dir=str(self.root))
        self.assertEqual(res["status"], "error")
        self.assertIn("Access denied", res.get("message", ""))

    def test_check_constraints_clean_code(self) -> None:
        """Test check_constraints approves valid SystemVerilog."""
        clean_sv = """
        module safe_pwm (
            input logic clk,
            input logic rst_n,
            input logic [9:0] sample,
            output logic aud_pwm
        );
            always_ff @(posedge clk) begin
                aud_pwm <= sample[9] ? 1'bz : 1'b0;
            end
        endmodule
        """
        res = check_constraints(clean_sv)
        self.assertEqual(res["status"], "success")
        self.assertTrue(res["clean"])
        self.assertEqual(res["violation_count"], 0)

    def test_check_constraints_violations(self) -> None:
        """Test check_constraints catches MicroBlaze and dangerous AUD_PWM driving."""
        bad_sv = """
        module bad_design;
            microblaze_0 cpu_inst();
            assign aud_pwm = 1'b1;
        endmodule
        """
        res = check_constraints(bad_sv)
        self.assertEqual(res["status"], "success")
        self.assertFalse(res["clean"])
        self.assertGreaterEqual(res["violation_count"], 2)
        rules = [v["rule"] for v in res["violations"]]
        self.assertIn("PROHIBITED_IP", rules)
        self.assertIn("ELECTRICAL_SAFETY", rules)

    def test_run_simulation_contract(self) -> None:
        """Test run_simulation outputs structured JSON with data delimiters."""
        res = run_simulation(project_root=str(self.root))
        self.assertIn("status", res)
        self.assertIn("mode", res)
        self.assertIn("data_wrapped", res)
        self.assertTrue(res["data_wrapped"].startswith("<DATA>"))
        self.assertTrue(res["data_wrapped"].endswith("</DATA>"))

    def test_stage_patch_contract(self) -> None:
        """Test stage_patch validates unified diff and constraints."""
        new_readme = "# Updated Readme Header\nLine 2\n"
        res = stage_patch("README.md", new_readme, project_root=str(self.root))
        self.assertEqual(res["status"], "success")
        self.assertTrue(res["constraints_clean"])
        self.assertIn("diff", res)
        self.assertTrue(res["data_wrapped"].startswith("<DATA>"))


    def test_sync_main_divergence_analysis(self) -> None:
        """Test analyze_main_divergence safely analyzes branch state."""
        res = analyze_main_divergence(base_branch="main", project_root=str(self.root))
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["base_branch"], "main")
        self.assertIn("safe_to_sync", res)
        self.assertIsInstance(res["colliding_files"], list)


if __name__ == "__main__":
    unittest.main()
