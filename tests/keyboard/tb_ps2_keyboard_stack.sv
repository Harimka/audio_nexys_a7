`timescale 1ns/1ps
module tb_ps2_keyboard_stack;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg ps2_clk = 1;
    reg ps2_data = 1;
    wire [3:0] digit;
    wire digit_valid;
    wire [2:0] note_index;
    wire [2:0] note_octave;
    wire note_event;
    wire note_down;

    integer note_on_count = 0;
    integer note_off_count = 0;
    reg [2:0] last_note = 0;
    reg [2:0] last_octave = 0;

    // Instantiate with held-note stack enabled (LEGATO_STACK = 1)
    ps2_keyboard_digit #(
        .FILTER_BITS(3),
        .TIMEOUT_CYCLES(2000),
        .LEGATO_STACK(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .digit(digit),
        .digit_valid(digit_valid),
        .note_index(note_index),
        .note_octave(note_octave),
        .note_event(note_event),
        .note_down(note_down)
    );

    always @(posedge clk) begin
        if (note_event) begin
            last_note   <= note_index;
            last_octave <= note_octave;
            if (note_down)
                note_on_count <= note_on_count + 1;
            else
                note_off_count <= note_off_count + 1;
        end
    end

    task tick(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task send_bit(input reg value);
        begin
            ps2_data = value;
            tick(8);
            ps2_clk = 0;
            tick(8);
            ps2_clk = 1;
            tick(8);
        end
    endtask

    task send_byte(input [7:0] value);
        integer i;
        reg parity;
        begin
            parity = ~(^value); // Odd parity
            send_bit(0);
            for (i = 0; i < 8; i = i + 1) send_bit(value[i]);
            send_bit(parity);
            send_bit(1);
            ps2_data = 1;
            tick(6);
        end
    endtask

    task press_key(input [7:0] scan_code, input [2:0] exp_note, input [2:0] exp_octave);
        integer on_before;
        begin
            on_before = note_on_count;
            send_byte(scan_code);
            if (note_on_count != on_before + 1 || !note_down ||
                note_index !== exp_note || note_octave !== exp_octave)
                $fatal(1, "press_key %02h: exp note=%0d oct=%0d, got note=%0d oct=%0d down=%b",
                       scan_code, exp_note, exp_octave, note_index, note_octave, note_down);
        end
    endtask

    task release_key(input [7:0] scan_code);
        begin
            send_byte(8'hF0);
            send_byte(scan_code);
        end
    endtask

    initial begin
        tick(4);
        rst_n = 1;
        tick(8);

        // 1. Single key press and release
        $display("[TEST 1] Single key press & release");
        press_key(8'h16, 3'd0, 3'd0); // 1 = C1
        release_key(8'h16);
        if (note_down !== 1'b0 || note_off_count != 1)
            $fatal(1, "TEST 1 failed: note did not turn off after release");

        // 2. Legato release: Releasing top note returns sound to previously held note
        $display("[TEST 2] Legato release: Key 1 held -> Key 2 pressed -> Key 2 released -> returns to Key 1");
        press_key(8'h16, 3'd0, 3'd0); // Key 1 = C1
        press_key(8'h1E, 3'd1, 3'd0); // Key 2 = D1 (now sounding)
        
        // Release Key 2 while Key 1 is STILL held
        release_key(8'h1E);
        tick(10);
        // Note must NOT stop! It must fall back to Key 1 (C1)
        if (!note_down || note_index !== 3'd0 || note_octave !== 3'd0)
            $fatal(1, "TEST 2 failed: releasing top note did not return sound to held Key 1");
        
        // Now release Key 1
        release_key(8'h16);
        tick(10);
        if (note_down !== 1'b0)
            $fatal(1, "TEST 2 failed: note did not stop after all keys released");

        // 3. Stale release: Releasing an older key does not interrupt currently playing top note
        $display("[TEST 3] Stale release: Key 1 held -> Key 2 pressed -> Key 1 released -> Key 2 continues");
        press_key(8'h16, 3'd0, 3'd0); // Key 1 = C1
        press_key(8'h1E, 3'd1, 3'd0); // Key 2 = D1 (top note)
        
        // Release Key 1 (older key)
        release_key(8'h16);
        tick(10);
        if (!note_down || note_index !== 3'd1 || note_octave !== 3'd0)
            $fatal(1, "TEST 3 failed: releasing older key interrupted active top note");

        // Release Key 2 -> sound stops
        release_key(8'h1E);
        tick(10);
        if (note_down !== 1'b0)
            $fatal(1, "TEST 3 failed: sound did not stop after last key released");

        // 4. Typematic repeat suppression
        $display("[TEST 4] Typematic auto-repeat suppression");
        begin : test_repeat
            integer on_before;
            press_key(8'h26, 3'd2, 3'd0); // Key 3 = E1
            on_before = note_on_count;
            // Send typematic repeats of 8'h26
            send_byte(8'h26);
            send_byte(8'h26);
            send_byte(8'h26);
            tick(10);
            if (note_on_count != on_before)
                $fatal(1, "TEST 4 failed: typematic repeat caused spurious note_event pulses (%0d -> %0d)",
                       on_before, note_on_count);
            release_key(8'h26);
        end

        // 5. 3-Key Chord Stack (C - E - G triad recall)
        $display("[TEST 5] 3-Key Chord stack: C1 -> E1 -> G1, unwinding stack");
        press_key(8'h16, 3'd0, 3'd0); // 1 = C1
        press_key(8'h26, 3'd2, 3'd0); // 3 = E1
        press_key(8'h2E, 3'd4, 3'd0); // 5 = G1
        
        // Release top key 5 -> returns to 3 (E1)
        release_key(8'h2E);
        tick(10);
        if (!note_down || note_index !== 3'd2)
            $fatal(1, "TEST 5 failed: release 5 did not return to 3 (E1)");

        // Release key 3 -> returns to 1 (C1)
        release_key(8'h26);
        tick(10);
        if (!note_down || note_index !== 3'd0)
            $fatal(1, "TEST 5 failed: release 3 did not return to 1 (C1)");

        // Release key 1 -> turns off
        release_key(8'h16);
        tick(10);
        if (note_down !== 1'b0)
            $fatal(1, "TEST 5 failed: release 1 did not turn off sound");

        $display("PASS ALL HELD-NOTE STACK TESTS (single, legato recall, stale release, typematic suppression, 3-key stack)");
        $finish;
    end
endmodule
