---
name: context_management
description: Skill for continuously maintaining, updating, and verifying agent context artifacts and project constraints during development.
---

# Agent Context Management & Artifact Actualization Skill

This skill governs how agents and developers maintain the project's living knowledge base (`harness/context/`). It ensures that whenever a module is inspected, modified, or tested, all discoveries, updated interface contracts, and architectural guardrails are permanently captured for all cooperating agents.

---

## 1. When to Use This Skill
- Before starting work on any module (to load current constraints and dependencies).
- Immediately after fixing a bug or implementing a new feature (to update [`PROJECT_STATUS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/PROJECT_STATUS.md)).
- Whenever a port, handshake, or timing contract changes (to update [`INTERFACES_CONTRACT.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/INTERFACES_CONTRACT.md)).

---

## 2. Core Context Artifacts to Maintain

1. **[`harness/context/CONSTRAINTS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/CONSTRAINTS.md)**:
   * Master registry of all hardware, electrical, IP, and synthesis constraints.
   * **Inviolable:** MicroBlaze forbidden, Block Design forbidden, permitted IP whitelist only, `AUD_PWM` 0/Z driving, VGA 800×600 timing.

2. **[`harness/context/PROJECT_STATUS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/PROJECT_STATUS.md)**:
   * Target hackathon criteria (Sound 45, VGA 25, Peripherals 20, Presentation 10).
   * Implemented modules vs pending work.
   * Defect tracker (Reset PLL bug, VGA VS porch bug, TB elaboration bug).
   * File navigation map.

3. **[`harness/context/INTERFACES_CONTRACT.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/INTERFACES_CONTRACT.md)**:
   * Clock frequencies (`sys_clk` 100 MHz, `clk_audio` ~49.152 MHz, `clk_vga` 50.0 MHz).
   * Audio streaming protocol (`valid && ready`, backpressure phase hold).
   * Safe cross-domain visualizer buffer (Dual-Port RAM).

4. **[`harness/context/TEAM_COLLABORATION.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/harness/context/TEAM_COLLABORATION.md)**:
   * Ownership distribution across 3 team members + agents.

---

## 3. Context Update Checklist

When modifying any RTL module or resolving a defect:
- [ ] 1. Check constraints against `CONSTRAINTS.md`.
- [ ] 2. Update `PROJECT_STATUS.md`: mark resolved defects as FIXED with commit hash / testbench verification evidence.
- [ ] 3. If port definitions or clock domains were modified, update `INTERFACES_CONTRACT.md`.
- [ ] 4. Run `python -m harness.tools.sync_main` to ensure zero collision with teammates.
