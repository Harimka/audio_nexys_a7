`timescale 1ns/1ps

module tb_audio_sample_player;

    localparam ADDR_WIDTH   = 6;        // 64 samples for fast simulation
    localparam DATA_WIDTH   = 16;
    localparam SAMPLE_DEPTH = 64;

    reg                   clk = 0;
    always #10 clk = ~clk; // 50 MHz simulation clock

    reg                   rst_n;
    reg                   play_trigger;
    reg                   stop_cmd;
    reg                   loop_en;
    reg                   ready;

    wire                  valid;
    wire [DATA_WIDTH-1:0] sample_out;
    wire                  playing;
    wire [ADDR_WIDTH-1:0] sample_addr;
    wire                  playback_end;

    // Golden memory model for verification
    reg [DATA_WIDTH-1:0] golden_mem [0:SAMPLE_DEPTH-1];
    integer i;

    // Instantiate DUT with 64 samples
    audio_sample_player #(
        .ADDR_WIDTH   ( ADDR_WIDTH   ),
        .DATA_WIDTH   ( DATA_WIDTH   ),
        .SAMPLE_DEPTH ( SAMPLE_DEPTH ),
        .INIT_FILE    ( ""           ) // Use internal init / test fill
    ) dut (
        .clk          ( clk          ),
        .rst_n        ( rst_n        ),
        .play_trigger ( play_trigger ),
        .stop_cmd     ( stop_cmd     ),
        .loop_en      ( loop_en      ),
        .ready        ( ready        ),
        .valid        ( valid        ),
        .sample_out   ( sample_out   ),
        .playing      ( playing      ),
        .sample_addr  ( sample_addr  ),
        .playback_end ( playback_end )
    );

    // Populate BRAM and golden model with identifiable pattern
    initial begin
        for (i = 0; i < SAMPLE_DEPTH; i = i + 1) begin
            golden_mem[i] = 16'h1000 + i * 16'h0010;
            dut.rom_inst.mem[i] = golden_mem[i];
        end
    end

    task tick(input integer count);
        repeat (count) @(posedge clk);
    endtask

    initial begin
        rst_n        = 0;
        play_trigger = 0;
        stop_cmd     = 0;
        loop_en      = 0;
        ready        = 0;

        tick(5);
        rst_n = 1;
        tick(5);

        // -------------------------------------------------------------
        // TEST 1: One-shot playback from sample 0 to 63
        // -------------------------------------------------------------
        $display("[TEST 1] One-shot playback with continuous ready");
        play_trigger = 1;
        tick(1);
        play_trigger = 0;
        ready = 1;

        // Wait until first valid sample appears
        while (!valid) @(posedge clk);
        for (i = 0; i < SAMPLE_DEPTH; i = i + 1) begin
            if (sample_addr !== i)
                $fatal(1, "[TEST 1] Sample %0d: expected addr %0d, got %0d", i, i, sample_addr);
            if (sample_out !== golden_mem[i])
                $fatal(1, "[TEST 1] Sample %0d: expected data %04h, got %04h", i, golden_mem[i], sample_out);
            if (i == SAMPLE_DEPTH - 1) begin
                if (!playback_end)
                    $fatal(1, "[TEST 1] Expected playback_end pulse at last sample");
            end
            tick(1);
        end

        // After last sample, player must return to IDLE
        tick(2);
        if (playing !== 1'b0 || valid !== 1'b0)
            $fatal(1, "[TEST 1] Expected player to stop after one-shot playback (playing=%b, valid=%b)", playing, valid);
        $display("  -> TEST 1 PASS");

        // -------------------------------------------------------------
        // TEST 2: Backpressure handling (ready de-asserted mid-stream)
        // -------------------------------------------------------------
        $display("[TEST 2] Backpressure handling: hold data under !ready");
        play_trigger = 1;
        tick(1);
        play_trigger = 0;
        ready = 1;

        // Play up to sample 10
        while (!(valid && sample_addr == 10)) @(posedge clk);
        #1;
        // Sample 11 is now presented; de-assert ready so sample 11 is frozen and held!
        ready = 0;
        begin : check_backpressure
            reg [DATA_WIDTH-1:0] held_sample;
            reg [ADDR_WIDTH-1:0] held_addr;
            held_sample = sample_out;
            held_addr   = sample_addr;

            repeat (10) begin
                tick(1);
                #1;
                if (sample_out !== held_sample || sample_addr !== held_addr || valid !== 1'b1)
                    $fatal(1, "[TEST 2] Backpressure violation: sample changed while !ready! (got %04h addr %0d, exp %04h addr %0d)",
                           sample_out, sample_addr, held_sample, held_addr);
            end

            // Release backpressure and verify seamless continuation
            ready = 1;
            tick(1);
            #1;
            if (sample_addr !== held_addr + 1 || sample_out !== golden_mem[held_addr + 1])
                $fatal(1, "[TEST 2] Expected sample %0d after backpressure release, got addr %0d data %04h",
                       held_addr + 1, sample_addr, sample_out);
        end

        // Drain remainder
        while (playing) @(posedge clk);
        tick(2);
        $display("  -> TEST 2 PASS");

        // -------------------------------------------------------------
        // TEST 3: Loop mode playback
        // -------------------------------------------------------------
        $display("[TEST 3] Loop mode playback: continuous wrap-around");
        loop_en = 1;
        play_trigger = 1;
        tick(1);
        play_trigger = 0;
        ready = 1;

        // Wait for first valid sample
        while (!valid) @(posedge clk);
        // Step through full buffer in loop mode and verify every single sample
        for (i = 0; i < SAMPLE_DEPTH; i = i + 1) begin
            if (sample_addr !== i)
                $fatal(1, "[TEST 3] Loop iter 1 sample %0d: expected addr %0d, got %0d", i, i, sample_addr);
            if (sample_out !== golden_mem[i])
                $fatal(1, "[TEST 3] Loop iter 1 sample %0d: expected data %04h, got %04h", i, golden_mem[i], sample_out);
            if (i == SAMPLE_DEPTH - 1) begin
                if (!playback_end)
                    $fatal(1, "[TEST 3] Expected playback_end at end of loop iteration 1");
            end
            tick(1);
        end

        // Next sample must wrap around to sample 0 seamlessly!
        if (sample_addr !== 0 || sample_out !== golden_mem[0] || !playing)
            $fatal(1, "[TEST 3] Expected loop wrap-around to sample 0, got addr %0d data %04h playing=%b",
                   sample_addr, sample_out, playing);

        tick(5);
        $display("  -> TEST 3 PASS");

        // -------------------------------------------------------------
        // TEST 4: Immediate stop command
        // -------------------------------------------------------------
        $display("[TEST 4] Immediate stop command");
        stop_cmd = 1;
        tick(1);
        stop_cmd = 0;
        tick(1);
        #1;

        if (playing !== 1'b0 || valid !== 1'b0 || sample_out !== 16'h8000)
            $fatal(1, "[TEST 4] Stop command failed: playing=%b, valid=%b, sample_out=%04h",
                   playing, valid, sample_out);
        $display("  -> TEST 4 PASS");

        $display("ALL AUDIO SAMPLE PLAYER TESTS PASSED SUCCESSFULLY!");
        $finish;
    end

endmodule
