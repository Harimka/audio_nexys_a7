---
name: systemverilog_rules
description: Strict guidelines and synthesis rules for writing clean, bug-free, synthesizable SystemVerilog code for Xilinx Artix-7 FPGAs in Vivado.
---

# Synthesizable SystemVerilog Guidelines for FPGA (Vivado / Artix-7)

This skill enforces strict hardware engineering standards when generating or reviewing SystemVerilog (`.sv`) RTL code for the `audio_nexys_a7` project.

---

## 1. Absolute Golden Rules of Synthesis

### Rule 1: Assignment Types (`=` vs `<=`)
- **Sequential Logic (Flip-Flops):** Inside `always_ff @(posedge clk ...)` **ALWAYS** use non-blocking assignment (`<=`).
- **Combinational Logic (Gates / Math):** Inside `always_comb` and `assign` **ALWAYS** use blocking assignment (`=`).
- **PROHIBITION:** NEVER mix `=` and `<=` for the same variable. NEVER use `=` inside `always_ff`.

### Rule 2: Zero-Latch Invariant (No Inadvertent Memory in Combinational Logic)
In `always_comb`, every signal that can be assigned MUST be assigned in all possible code branches.
- **Pattern:** Assign a default value at the very top of the `always_comb` block before any `if` or `case` statements.
- **Exhaustive Cases:** Every `case` statement MUST have a `default:` branch.
- **Exhaustive Conditionals:** Every `if` statement without top-level default must have an `else` branch.

### Rule 3: Clocking and Clock Enables (No Ripple Clocks)
- **NEVER** use the output of a counter or combinatorial logic as a clock input (`@(posedge count[24])`). This creates severe clock skew, routing delays, and Vivado timing failures.
- **ALWAYS** run modules on the primary clock (`clk`) and use a 1-clock-cycle pulse **Clock Enable (`CE`)**:
  ```systemverilog
  // CORRECT: Clock Enable
  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          sample_out <= '0;
      end else if (enable_48khz) begin
          sample_out <= next_sample;
      end
  end
  ```

### Rule 4: Clock Domain Crossing (CDC)
- Signals generated in one clock domain (`sys_clk`, `clk_audio`, `pixel_clk`) CANNOT be read directly in another clock domain.
- **Single-bit control pulses:** Use a 2-stage flip-flop synchronizer (2-FF).
- **Multi-bit buses / Data words / Waveforms:**
  * Simple 2-FF on multi-bit buses is **STRICTLY PROHIBITED** (violates bus coherency).
  * Use **Dual-Port RAM** (Port A writes on `clk_src`, Port B reads on `clk_dst`) or an asynchronous FIFO with Gray-coded pointers.

### Rule 5: Reset Discipline
- All resets in this project are active-low: `rst_n`.
- Reset de-assertion MUST be synchronous to the respective clock domain (use `reset_sync.sv`).
- Whenever PLL loses lock (`locked == 1'b0`), `rst_n` must assert immediately.

### Rule 6: Hardware Safety & Electrical Rules
- **`AUD_PWM` Output:** MUST ALWAYS be assigned as `0` or `1'bz` (open-drain emulation):
  ```systemverilog
  assign AUD_PWM = pwm_pulse ? 1'bz : 1'b0; // NEVER 1'b1!
  ```
- **Prohibited Architectures:** MicroBlaze soft-core CPU and Vivado Block Design are STRICTLY FORBIDDEN.

---

## 2. Non-Synthesizable Constructs (Prohibited in RTL)

The following constructs exist in SystemVerilog for PC simulation only and will **FAIL in Vivado synthesis**:
* ❌ Delays (`#10`, `#5ns`)
* ❌ Dynamic memory allocation (`new()`, dynamic arrays, associative arrays)
* ❌ Dynamic classes and virtual methods (`class`, `virtual function`, `extends` inside synthesizable modules)
* ❌ `fork ... join` parallel blocks
* ❌ Non-constant `initial` loops (only `$readmemh` / `$readmemb` for ROM initialization is allowed in `initial`).

---

## 3. Canonical Module Template

When creating a new SystemVerilog module, use this exact clean structure:

```systemverilog
`timescale 1ns / 1ps

module my_hardware_module #(
    parameter int DATA_WIDTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,
    
    // Control / Handshake
    input  logic                  enable,
    input  logic [DATA_WIDTH-1:0] data_in,
    
    output logic [DATA_WIDTH-1:0] data_out,
    output logic                  valid_out
);

    // 1. Internal registers and nets
    logic [DATA_WIDTH-1:0] data_reg;
    logic                  valid_reg;

    // 2. Sequential Logic (Memory & State)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg  <= '0;
            valid_reg <= 1'b0;
        end else if (enable) begin
            data_reg  <= data_in;
            valid_reg <= 1'b1;
        end else begin
            valid_reg <= 1'b0;
        end
    end

    // 3. Continuous Output Assignments
    assign data_out  = data_reg;
    assign valid_out = valid_reg;

endmodule
```
