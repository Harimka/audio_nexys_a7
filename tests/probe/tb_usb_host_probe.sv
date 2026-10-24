`timescale 1ns/1ps
module tb_usb_host_probe;
    reg CLK100MHZ = 0;
    always #5 CLK100MHZ = ~CLK100MHZ;
    reg CPU_RESETN = 0;
    reg PS2_CLK = 1, PS2_DATA = 1;
    reg [1:0] SW = 0;
    wire [15:0] LED;
    wire [7:0] AN;
    wire CA, CB, CC, CD, CE, CF, CG, DP, AUD_PWM, AUD_SD;
    audio_nexys_a7 #(.STARTUP_BITS(4), .SCAN_BITS(2),
                    .TIMEOUT_CYCLES(2000)) dut (.*);
    task automatic tick(input integer n);
        repeat(n) @(negedge CLK100MHZ);
    endtask
    task automatic bit_out(input bit b);
        PS2_DATA = b; tick(20);
        PS2_CLK = 0; tick(20);
        PS2_CLK = 1; tick(20);
    endtask
    task automatic frame(input [7:0] b, input bit bad_parity, input bit bad_stop);
        integer i;
        bit_out(0);
        for (i=0;i<8;i=i+1) bit_out(b[i]);
        bit_out((~^b) ^ bad_parity);
        bit_out(!bad_stop);
        PS2_DATA = 1; tick(30);
    endtask
    task automatic check_scan(input [31:0] expected);
        integer i, digit;
        reg [7:0] seen, active;
        reg [6:0] actual;
        // Wait for a coherent new snapshot (at most 32 cycles at SCAN_BITS=2).
        tick(70); seen=0;
        for (i=0;i<40;i=i+1) begin
            tick(1);
            for (digit=0;digit<8;digit=digit+1)
                if (AN == ~(8'b1 << digit)) begin
                    actual={CG,CF,CE,CD,CC,CB,CA};
                    if (actual != dut.hex_segments(expected[digit*4 +: 4]))
                        $fatal(1,"digit %0d mismatch for %h",digit,expected);
                    seen[digit]=1;
                end
            // Exactly one anode active, no extra active bits.
            active = ~AN;
            if ((active & (active-8'd1)) != 0) $fatal(1,"multiple anodes active");
        end
        if (seen != 8'hFF) $fatal(1,"not all digits scanned");
    endtask
    initial begin
        tick(4); CPU_RESETN=1; tick(40);
        if (dut.frames != 0 || dut.edges != 0 || dut.errors != 0)
            $fatal(1,"idle lines produced data");
        if (AUD_SD !== 0 || AUD_PWM !== 1'bz || DP !== 1)
            $fatal(1,"probe must keep audio muted and DP off");
        // One-clock noise is below the 8-sample input filter threshold.
        PS2_CLK=0; tick(1); PS2_CLK=1; tick(40);
        if (dut.edges != 0) $fatal(1,"short clock glitch accepted");
        frame(8'hAB,0,0); frame(8'hCD,0,0);
        if (dut.frames != 2 || dut.last_two != 16'hABCD || dut.edges != 22)
            $fatal(1,"valid frame count/history/edge count mismatch");
        if (!LED[12] || !LED[11] || !LED[10] || LED[7:0] != 8'hCD)
            $fatal(1,"activity LEDs did not latch");
        check_scan(32'h0002ABCD);
        frame(8'h5A,1,0);
        frame(8'h5A,0,1);
        if (dut.frames != 2 || dut.errors != 2 || dut.last_two != 16'hABCD)
            $fatal(1,"bad parity/stop should not update last bytes");
        bit_out(0); PS2_DATA=1; tick(2100);
        if (dut.timeouts != 1 || !LED[8]) $fatal(1,"partial frame timeout missing");
        frame(8'h90,0,0); frame(8'd48,0,0); frame(8'd36,0,0);
        if (!dut.gate || dut.active_note != 48 || dut.active_velocity != 36)
            $fatal(1,"MIDI candidate page did not decode injected bytes");
        SW=2'b10; tick(10); check_scan(32'h10048036);
        frame(8'h80,0,0); frame(8'd48,0,0); frame(8'd57,0,0);
        if (dut.gate) $fatal(1,"injected release did not clear candidate gate");
        tick(10); check_scan(32'h00048000);
        SW=2'b01; tick(10);
        if (dut.display_word != {dut.edges,dut.errors,dut.timeouts})
            $fatal(1,"statistics page mismatch");
        SW=2'b11; tick(10); check_scan(32'h12345678);
        // Synchronous release and manual reset clear counters and note state.
        CPU_RESETN=0; tick(5);
        if (dut.frames != 0 || dut.gate || dut.errors != 0 || dut.timeouts != 0)
            $fatal(1,"CPU RESET did not clear state");
        CPU_RESETN=1; tick(40);
        if (dut.frames != 0) $fatal(1,"state reappeared after reset");
        $display("PASS probe: passive PS/2, glitch filter, valid/parity/stop/timeout, counters, history, LEDs, 8-digit scan/pages, synthetic MIDI candidate, reset, audio muted");
        $finish;
    end
    initial begin #1000000; $fatal(1,"probe timeout"); end
endmodule
