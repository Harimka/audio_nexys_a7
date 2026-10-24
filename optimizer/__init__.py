"""Harness² optimizer package for recursive agent adaptation."""

from .composer import Composer
from .loop import OptimizationLoop
from .probe import ProbeExecutor
from .proposer import DeterministicProposer
from .spec import CandidateProposal, LedgerEntry, ProbeResult, SurfaceSpec
from .tree import diff_trees, read_harness, write_harness

__all__ = [
    "CandidateProposal",
    "Composer",
    "DeterministicProposer",
    "LedgerEntry",
    "OptimizationLoop",
    "ProbeExecutor",
    "ProbeResult",
    "SurfaceSpec",
    "diff_trees",
    "read_harness",
    "write_harness",
]
