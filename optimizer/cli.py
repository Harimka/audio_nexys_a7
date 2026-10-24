"""Command-line interface for the Harness² recursive optimizer."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .loop import OptimizationLoop


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Harness² Recursive Agent Optimizer",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--task",
        type=str,
        default="reset",
        help="Target benchmark task ('reset', 'vga', 'all')",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=2,
        help="Number of recursive Propose -> Probe -> Compose iterations",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=".",
        help="Root path of the repository",
    )
    parser.add_argument(
        "--mode",
        choices=["run", "demo"],
        default="run",
        help="Execution mode ('run' for standard optimization, 'demo' for quick verification)",
    )

    args = parser.parse_args()
    root_path = Path(args.root).resolve()

    print("=================================================")
    print(" Harness^2 Recursive Optimizer: audio_nexys_a7")
    print(f" Mode: {args.mode} | Task: {args.task} | Iterations: {args.iterations}")
    print("=================================================")

    loop = OptimizationLoop(root=root_path)
    result = loop.run(task_id=args.task, iterations=args.iterations)

    print("\n--- OPTIMIZATION RESULTS ---")
    print(f"Task: {result['task_id']}")
    print(f"Initial Score: {result['initial_score']:.2f} -> Final Score: {result['final_score']:.2f}")
    print(f"Accepted Candidates: {result['accepted_count']} / {result['iterations_executed']}")
    print("\nHistory:")
    for h in result["history"]:
        status_sym = "[ACCEPTED]" if h["accepted"] else "[REJECTED]"
        print(f"  Iteration {h['iteration']}: {status_sym} {h['candidate_id']} - {h['contrastive_notes']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
