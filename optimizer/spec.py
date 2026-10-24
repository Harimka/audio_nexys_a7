"""Specifications, data contracts, and schemas for Harness² optimizer."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HarnessTree = Dict[str, str]

EDITABLE_COMPONENTS = (
    "systemprompt.md",
    "guardrails.md",
    "memory/operational_memory.md",
    "skills/prompt_engineering/SKILL.md",
    "skills/rtl_verification/SKILL.md",
)


@dataclass(frozen=True)
class SurfaceSpec:
    """Defines the editable surface of the agent harness."""

    name: str = "audio_nexys_harness"
    harness_dir: str = "harness"
    always_on: Tuple[str, ...] = EDITABLE_COMPONENTS
    tools_dir: str = "harness/tools"
    skills_dir: str = "harness/skills"
    memory_dir: str = "harness/memory"


@dataclass
class CandidateProposal:
    """A proposed modification to the harness tree."""

    id: str
    rationale: str
    edits: Dict[str, str]  # relative path within harness -> new content
    diffs: Dict[str, str] = field(default_factory=dict)


@dataclass
class ProbeResult:
    """The outcome of probing a harness candidate against evaluation tasks."""

    candidate_id: str
    status: str  # "success" | "error"
    score: float  # 0.0 to 1.0
    passed_cases: List[str] = field(default_factory=list)
    failed_cases: List[str] = field(default_factory=list)
    output: str = ""
    exit_code: int = 0
    duration_s: float = 0.0
    error_message: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "candidate_id": self.candidate_id,
            "status": self.status,
            "score": self.score,
            "passed_cases": self.passed_cases,
            "failed_cases": self.failed_cases,
            "exit_code": self.exit_code,
            "duration_s": self.duration_s,
            "error_message": self.error_message,
        }


@dataclass
class LedgerEntry:
    """Immutable record of an optimization iteration."""

    iteration: int
    candidate_id: str
    rationale: str
    accepted: bool
    baseline_score: float
    candidate_score: float
    contrastive_notes: str
    diff_summary: Dict[str, str]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "iteration": self.iteration,
            "candidate_id": self.candidate_id,
            "rationale": self.rationale,
            "accepted": self.accepted,
            "baseline_score": self.baseline_score,
            "candidate_score": self.candidate_score,
            "contrastive_notes": self.contrastive_notes,
            "diff_summary": self.diff_summary,
        }
