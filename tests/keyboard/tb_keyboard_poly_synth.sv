`timescale 1ns/1ps
module tb_keyboard_poly_synth;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg note_event = 0;
    reg note_down = 0;
    reg [7:0] note_key = 0;
    reg [2:0] note_index = 0;
    reg [2:0] note_octave = 3;
    reg ready = 1;
    wire [15:0] sample;
    wire [3:0] active_count;
    wire [27:0] active_pitch_mask;

    keyboard_poly_synth #(.VOICES(8)) dut (
        .clk(clk), .rst_n(rst_n), .note_event(note_event),
        .note_down(note_down), .note_key(note_key), .note_index(note_index),
        .note_octave(note_octave), .ready(ready), .sample(sample),
        .active_count(active_count)
    );

    task event_key(input reg down, input [7:0] key, input [2:0] note,
                   input [2:0] octave);
        begin
            @(negedge clk);
            note_down = down;
            note_key = key;
            note_index = note;
            note_octave = octave;
            note_event = 1;
            @(negedge clk);
            note_event = 0;
            @(posedge clk); #1;
        end
    endtask

    initial begin : test
        reg [15:0] first_sample;
        integer k;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;
        if (active_count != 0 || sample != 16'd32768)
            $fatal(1, "reset state should be silence with midpoint sample");

        // C major triad: C4, E4, G4. Each key gets an independent DDS voice.
        event_key(1, 8'h1A, 3'd0, 3'd3);
        event_key(1, 8'h21, 3'd2, 3'd3);
        event_key(1, 8'h32, 3'd4, 3'd3);
        if (active_count != 3) $fatal(1, "triad should allocate three voices");
        first_sample = sample;
        for (k = 0; k < 100; k = k + 1) @(posedge clk);
        #1;
        if (sample === first_sample)
            $fatal(1, "mixed chord sample did not advance");

        // Releasing E must leave C and G sounding.
        event_key(0, 8'h21, 3'd2, 3'd3);
        if (active_count != 2) $fatal(1, "releasing one chord key stopped other voices");
        event_key(0, 8'h1A, 3'd0, 3'd3);
        if (active_count != 1) $fatal(1, "second matching key release failed");
        event_key(0, 8'h32, 3'd4, 3'd3);
        if (active_count != 0 || sample != 16'd32768)
            $fatal(1, "all voices released should return to silence");

        // A key release is matched by scan code, never by pitch alone.
        event_key(1, 8'h16, 3'd0, 3'd0);
        event_key(1, 8'h1A, 3'd0, 3'd3);
        event_key(0, 8'h16, 3'd0, 3'd0);
        if (active_count != 1) $fatal(1, "same pitch in another octave was released");
        event_key(0, 8'h1A, 3'd0, 3'd3);
        if (active_count != 0) $fatal(1, "final voice did not release");

        $display("PASS keyboard poly synth: triad mixing, independent release, and octave/key identity");
        $finish;
    end
endmodule
