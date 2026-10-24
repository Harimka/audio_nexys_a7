`timescale 1ns / 1ps

module tb_audio_scope_buffer;

    reg clk_audio = 0;
    always #10.17 clk_audio = ~clk_audio; // ~49.152 MHz (20.34 ns)

    reg pixel_clk = 0;
    always #12.52 pixel_clk = ~pixel_clk; // ~39.941 MHz (25.04 ns)

    reg        aud_rst_n = 0;
    reg        pix_rst_n = 0;
    reg        sample_tick = 0;
    reg [7:0]  audio_sample = 8'd128;
    reg        audio_play = 0;
    reg        frame_sync = 0;
    reg [7:0]  scope_x = 0;
    wire [7:0] scope_sample;

    audio_scope_buffer dut (
        .clk_audio    ( clk_audio    ),
        .aud_rst_n    ( aud_rst_n    ),
        .sample_tick  ( sample_tick  ),
        .audio_sample ( audio_sample ),
        .audio_play   ( audio_play   ),
        .pixel_clk    ( pixel_clk    ),
        .pix_rst_n    ( pix_rst_n    ),
        .frame_sync   ( frame_sync   ),
        .scope_x      ( scope_x      ),
        .scope_sample ( scope_sample )
    );

    integer i;

    // Pulse sample_tick every ~1024 audio clocks
    task automatic tick_sample(input [7:0] val);
        begin
            audio_sample = val;
            @(posedge clk_audio);
            sample_tick = 1'b1;
            @(posedge clk_audio);
            sample_tick = 1'b0;
            #100;
        end
    endtask

    initial begin
        $display("START AUDIO SCOPE BUFFER TEST");

        // 1. Reset
        aud_rst_n = 0;
        pix_rst_n = 0;
        #100;
        aud_rst_n = 1;
        pix_rst_n = 1;
        #100;

        // 2. Silence capture test: audio_play = 0
        audio_play = 0;
        @(posedge pixel_clk);
        frame_sync = 1;
        @(posedge pixel_clk);
        frame_sync = 0;
        #200;

        // Feed 300 sample ticks during silence
        for (i = 0; i < 300; i = i + 1) begin
            tick_sample(8'd128);
        end

        // Check that RAM outputs 128 (silence) across all X
        for (i = 0; i < 234; i = i + 1) begin
            scope_x = i;
            #5;
            if (scope_sample !== 8'd128) begin
                $display("FAIL: Silence check failed at x=%0d, got %0d", i, scope_sample);
                $fatal(1);
            end
        end
        $display("PASS: Silence check (all samples 128)");

        // 3. Active audio waveform capture with trigger
        audio_play = 1;
        @(posedge pixel_clk);
        frame_sync = 1;
        @(posedge pixel_clk);
        frame_sync = 0;
        #200;

        // Feed below-threshold samples first (90)
        tick_sample(8'd90);
        tick_sample(8'd100);
        tick_sample(8'd110);

        // Rising zero-crossing: jumps from 110 to 140
        tick_sample(8'd140);

        // Feed a ramp of samples
        for (i = 1; i < 256; i = i + 1) begin
            tick_sample(8'd140 + i[7:0]);
        end

        // Verify captured samples
        scope_x = 0;
        #10;
        if (scope_sample !== 8'd140) begin
            $display("FAIL: Trigger sample at x=0 should be 140, got %0d", scope_sample);
            $fatal(1);
        end
        $display("PASS: Triggered capture sample at x=0 = %0d", scope_sample);

        scope_x = 10;
        #10;
        if (scope_sample !== 8'd150) begin
            $display("FAIL: Sample at x=10 should be 150, got %0d", scope_sample);
            $fatal(1);
        end
        $display("PASS: Sample at x=10 = %0d", scope_sample);

        $display("ALL AUDIO SCOPE BUFFER TESTS PASSED!");
        $finish;
    end

endmodule
