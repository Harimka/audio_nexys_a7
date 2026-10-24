`timescale 1ns/1ps
module tb_melody_recorder;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg sample_tick = 0;
    reg record_toggle = 0;
    reg play_trigger = 0;
    reg play_stop = 0;
    reg key_event = 0;
    reg key_down = 0;
    reg [7:0] key_id = 0;
    reg [2:0] note_index = 0;
    reg [2:0] note_octave = 3;
    reg [1:0] note_waveform = 0;
    reg event_ready = 1;
    wire event_valid, event_down, recording, playing;
    wire [7:0] event_key;
    wire [2:0] event_note_index, event_note_octave;
    wire [1:0] event_waveform;
    wire [6:0] event_count;
    wire [4:0] preview_count;
    wire [79:0] preview_notes;
    wire [895:0] roll_matrix;
    integer observed = 0;
    integer i;
    reg [1:0] seen_down;
    reg [7:0] seen_key [0:1];

    melody_recorder #(.EVENT_DEPTH(64)) dut (.*);

    always @(posedge clk) begin
        if (event_valid && event_ready) begin
            if (observed < 2) begin
                seen_down[observed] <= event_down;
                seen_key[observed] <= event_key;
            end
            observed <= observed + 1;
        end
    end

    task pulse_record;
        begin @(negedge clk); record_toggle=1; @(negedge clk); record_toggle=0; end
    endtask
    task pulse_play;
        begin @(negedge clk); play_trigger=1; @(negedge clk); play_trigger=0; end
    endtask
    task pulse_key(input reg down, input [7:0] key, input [2:0] note, input [2:0] octave);
        begin
            @(negedge clk); key_event=1; key_down=down; key_id=key;
            note_index=note; note_octave=octave;
            @(negedge clk); key_event=0;
        end
    endtask
    task tick_samples(input integer n);
        integer k;
        begin
            for (k=0; k<n; k=k+1) begin
                @(negedge clk); sample_tick=1;
                @(negedge clk); sample_tick=0;
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst_n=1;
        pulse_record();
        if (!recording) $fatal(1, "F9 did not start recording");
        tick_samples(3);
        pulse_key(1, 8'h16, 3'd0, 3'd0);
        tick_samples(5);
        pulse_key(0, 8'h16, 3'd0, 3'd0);
        pulse_record();
        if (recording || event_count != 2)
            $fatal(1, "recording should close with two key transitions");

        observed=0;
        pulse_play();
        tick_samples(2);
        if (observed != 0) $fatal(1, "first note played before its recorded delay");
        tick_samples(1);
        wait (observed == 1);
        if (!seen_down[0] || seen_key[0] != 8'h80)
            $fatal(1, "playback did not emit tagged note-on");
        tick_samples(4);
        if (observed != 1) $fatal(1, "second note event played before its recorded delay");
        tick_samples(1);
        wait (observed == 2);
        if (seen_down[1] || seen_key[1] != 8'h80)
            $fatal(1, "playback did not emit matching tagged note-off");
        wait (!playing && !dut.cleanup_pending);

        // Escape midway through a take must synthesize a matching release so
        // the shared polyphonic allocator cannot leave a voice hanging.
        observed=0;
        pulse_record();
        pulse_key(1, 8'h21, 3'd2, 3'd3);
        pulse_record();
        pulse_play();
        wait (observed == 1);
        if (!seen_down[0] || seen_key[0] != (8'h80 + dut.playback_key_index(8'h21)))
            $fatal(1, "second take did not start on the recorded key");
        @(negedge clk); play_stop=1;
        @(negedge clk); play_stop=0;
        wait (observed == 2);
        if (seen_down[1] || seen_key[1] != (8'h80 + dut.playback_key_index(8'h21)))
            $fatal(1, "Escape failed to release an active sequence voice");
        wait (!playing && !dut.cleanup_pending);

        // Verify the advertised capacity: 32 complete Note On/Off pairs.
        pulse_record();
        for (i=0; i<32; i=i+1) begin
            pulse_key(1, i[7:0], i[2:0], i[1:0]);
            pulse_key(0, i[7:0], i[2:0], i[1:0]);
        end
        if (recording || event_count != 64)
            $fatal(1, "recording capacity should hold 64 transitions / 32 note pairs");
        pulse_key(1, 8'h55, 3'd1, 3'd1);
        if (event_count != 64)
            $fatal(1, "events beyond the fixed buffer should be ignored");
        $display("PASS melody recorder: 64-event storage interface, event timing, key identity and playback");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "timeout waiting for recorded melody playback");
    end
endmodule
