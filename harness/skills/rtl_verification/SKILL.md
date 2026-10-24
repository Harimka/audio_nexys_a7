---
name: rtl_verification
description: Domain skill for auditing, verifying, and testing SystemVerilog RTL modules against timing and simulation benchmarks.
---

# RTL Verification & Diagnostic Skill

This skill provides step-by-step guidance for diagnosing and fixing SystemVerilog modules within the `audio_nexys_a7` project.

## Verification Checklist

1. **Interface Compliance**:
   - Verify whether handshake signals (`valid` and `ready`) conform to the protocol:
     - Transaction occurs strictly on `(valid && ready)`.
     - Data must remain held and unchanged whenever `valid && !ready`.
     - Internal phase counters (e.g. DDS accumulator in `tone_generator.sv`) must pause incrementing when `!ready`.

2. **Reset & Clock Domain Safety**:
   - Active-low vs active-high resets: inspect whether `rst_n` is properly conditioned.
   - Synchronous de-assertion: ensure reset release is synchronized to the destination clock.
   - Lock loss handling: if PLL lock de-asserts, reset must assert immediately.

3. **VGA Geometry Check (800×600 @ 72 Hz standard)**:
   - Pixel clock: 50.0 MHz
   - Horizontal: Active 800, Front Porch 56, Sync Pulse 120, Back Porch 64 (Total 1040 or 1056 depending on porch mode).
   - Vertical: Active 600, Front Porch 37, Sync Pulse 6, Back Porch 23 (Total 666) or target 1056x628 total as specified in baseline logs.
   - Check sync pulse polarities.

4. **PWM Output Safety**:
   - Ensure the tristate buffer drives `AUD_PWM = pwm_bit ? 1'bz : 1'b0`.
   - Never assign `AUD_PWM = 1'b1`.
