`timescale 1ns / 1ps

module tb_audio_nexys_a7 ();
  bit               CLK100MHZ;
  bit               PS2_CLK = 1'b1;
  bit               PS2_DATA = 1'b1;
  bit     [15:0]    SW;
  //
  logic             DP, CG, CF, CE, CD, CC, CB, CA;
  logic   [ 7:0]    AN;
  //
  bit               BTNC, BTNU, BTNL, BTNR, BTND, CPU_RESETN;
  //
  logic             AUD_PWM;
  logic             AUD_SD;
  logic   [ 3:0]    VGA_R, VGA_G, VGA_B;
  logic             VGA_HS, VGA_VS;

  //----------- CLK: 100 MHz (period = 10 ns) -//
  always #5 CLK100MHZ = ~CLK100MHZ;

  //----------- Main Initial -//
  initial begin
    CLK100MHZ = 1'b0;
    CPU_RESETN = 1'b1;
    SW = 16'h0000;
    BTNC = 1'b0;
    BTNU = 1'b0;
    BTNL = 1'b0;
    BTNR = 1'b0;
    BTND = 1'b0;

    #10;
    CPU_RESETN = 1'b0;
    // To pass reset through button debouncer we need 2^16 * 10ns = ~656us
    #656000;
    CPU_RESETN = 1'b1;

    #100000;
    $display("PASS testbench execution finished successfully");
    $finish;
  end

  //----------- DUT
  audio_nexys_a7 dut (
    .*
  );

endmodule
