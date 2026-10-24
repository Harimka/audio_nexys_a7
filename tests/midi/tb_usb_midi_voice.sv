`timescale 1ns/1ps
module tb_usb_midi_voice;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] packet_data = 0;
    reg packet_valid = 0;
    wire packet_ready, packet_error;
    reg sample_ready = 1;
    wire [15:0] sample;
    wire gate;
    wire [3:0] channel;
    wire [6:0] note, velocity;
    usb_midi_voice dut (.*);
    task automatic send(input [31:0] p);
        @(negedge clk); packet_data = p; packet_valid = 1;
        while (!packet_ready) @(negedge clk);
        @(negedge clk); packet_valid = 0;
        repeat (3) @(negedge clk);
    endtask
    integer i, crossings, lo, hi;
    reg [15:0] previous, held_sample;
    initial begin
        #1; rst_n = 0; #10; rst_n = 1;
        repeat (3) @(negedge clk);
        if (sample != 32768 || gate) $fatal(1, "reset is not silent");
        // Cable 0, channel 0, A4=69, velocity=100.
        send(32'h64459009);
        if (!gate || note != 69 || velocity != 100 || channel != 0 || packet_error)
            $fatal(1, "USB payload did not reach wavetable voice");
        crossings = 0; lo = 65535; hi = 0; previous = sample;
        // 96013 accepted samples ~= 2 seconds at 49158650/1024 samples/s.
        for (i = 0; i < 96013; i = i + 1) begin
            @(negedge clk);
            if (previous < 32768 && sample >= 32768) crossings = crossings + 1;
            previous = sample;
            if (sample < lo) lo = sample;
            if (sample > hi) hi = sample;
        end
        if (crossings < 879 || crossings > 881)
            $fatal(1, "A4 frequency mismatch: %0d cycles in 2 seconds", crossings);
        if (lo < 7100 || lo > 7300 || hi < 58200 || hi > 58500)
            $fatal(1, "velocity scaling mismatch: min=%0d max=%0d", lo, hi);
        sample_ready = 0; held_sample = sample;
        repeat (100) begin
            @(negedge clk);
            if (sample != held_sample) $fatal(1, "sample advanced under backpressure");
        end
        sample_ready = 1;
        send(32'h00458108); // Another channel: keep sounding.
        if (!gate) $fatal(1, "wrong channel muted USB voice");
        send(32'h39458008); // Matching Note Off with nonzero release velocity.
        if (gate || sample != 32768) $fatal(1, "Note Off did not silence voice");
        send(32'h24309009); // User's observed note 48, velocity 36.
        if (!gate || note != 48 || velocity != 36)
            $fatal(1, "observed MicroLab packet failed");
        @(negedge clk); rst_n = 0; #1;
        if (gate || sample != 32768) $fatal(1, "disconnect reset did not silence voice");
        $display("PASS USB payload -> wavetable: A4 ~440 Hz, velocity, sample backpressure, matching release, disconnect reset (not physical USB host)");
        $finish;
    end
    initial begin #2000000; $fatal(1, "voice timeout"); end
endmodule
