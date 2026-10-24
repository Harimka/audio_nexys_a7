`timescale 1ns/1ps
module tb_ps2_keyboard_digit;
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
    wire [7:0] note_key;
    integer valid_count = 0;
    integer note_on_count = 0;
    integer note_off_count = 0;
    reg [3:0] last_digit = 0;
    reg [2:0] last_note = 0;
    reg [2:0] last_octave = 0;
    reg [7:0] last_key = 0;

    ps2_keyboard_digit #(.FILTER_BITS(3), .TIMEOUT_CYCLES(2000)) dut (
        .clk(clk), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .digit(digit), .digit_valid(digit_valid),
        .note_index(note_index), .note_octave(note_octave),
        .note_event(note_event), .note_down(note_down), .note_key(note_key)
    );

    always @(posedge clk) begin
        if (digit_valid) begin
            valid_count <= valid_count + 1;
            last_digit <= digit;
        end
        if (note_event) begin
            last_note <= note_index;
            last_octave <= note_octave;
            last_key <= note_key;
            if (note_down) note_on_count <= note_on_count + 1;
            else note_off_count <= note_off_count + 1;
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
            parity = ~(^value); // Set 2 uses odd parity.
            send_bit(0);
            for (i = 0; i < 8; i = i + 1) send_bit(value[i]);
            send_bit(parity);
            send_bit(1);
            ps2_data = 1;
            tick(6);
        end
    endtask

    task check_digit(input [7:0] scan_code, input [3:0] expected);
        integer count_before;
        begin
            count_before = valid_count;
            send_byte(scan_code);
            if (valid_count != count_before + 1 || last_digit !== expected || digit !== expected)
                $fatal(1, "scan %02h: expected digit %0d, got %0d (events %0d -> %0d)",
                       scan_code, expected, digit, count_before, valid_count);
        end
    endtask

    task check_note(input [7:0] scan_code, input [2:0] expected,
                    input [2:0] expected_octave);
        integer on_before;
        begin
            on_before = note_on_count;
            send_byte(scan_code);
            if (note_on_count != on_before + 1 || last_note !== expected ||
                last_octave !== expected_octave || note_index !== expected ||
                note_octave !== expected_octave || !note_down)
                $fatal(1, "scan %02h: expected note %0d octave %0d, got note %0d octave %0d",
                       scan_code, expected, expected_octave, note_index, note_octave);
        end
    endtask

    task release_note(input [7:0] scan_code);
        integer off_before;
        begin
            off_before = note_off_count;
            send_byte(8'hF0);
            send_byte(scan_code);
            if (note_off_count != off_before + 1 || note_down)
                $fatal(1, "scan %02h: expected matching Note Off", scan_code);
        end
    endtask

    initial begin
        tick(4);
        rst_n = 1;
        tick(8);

        check_digit(8'h16, 1);
        check_digit(8'h1E, 2);
        check_digit(8'h26, 3);
        check_digit(8'h25, 4);
        check_digit(8'h2E, 5);
        check_digit(8'h36, 6);
        check_digit(8'h3D, 7);
        check_digit(8'h3E, 8);
        check_digit(8'h46, 9);
        check_digit(8'h45, 0);

        // Break sequences must not overwrite the last displayed digit.
        send_byte(8'hF0);
        begin : check_release
            integer count_before;
            count_before = valid_count;
            send_byte(8'h16);
            if (valid_count != count_before || digit !== 0)
                $fatal(1, "key release changed the displayed value");
        end
        if (dut.note_keys_down[8'h16]) $fatal(1, "top-row 1 remained logically held after break");

        // Numeric keypad scan codes map to the same decimal digits.
        check_digit(8'h70, 0);
        check_digit(8'h69, 1);
        check_digit(8'h72, 2);
        check_digit(8'h7A, 3);
        check_digit(8'h6B, 4);
        check_digit(8'h73, 5);
        check_digit(8'h74, 6);
        check_digit(8'h6C, 7);
        check_digit(8'h75, 8);
        check_digit(8'h7D, 9);

        // Clear musical key-down state caused by number-row digit checks.
        send_byte(8'hF0); send_byte(8'h1E);
        send_byte(8'hF0); send_byte(8'h26);
        send_byte(8'hF0); send_byte(8'h25);
        send_byte(8'hF0); send_byte(8'h2E);
        send_byte(8'hF0); send_byte(8'h36);
        send_byte(8'hF0); send_byte(8'h3D);

        // The first seven keys of each physical row select C..B in octaves 1..4.
        check_note(8'h16, 3'd0, 3'd0); // 1 = C1
        check_note(8'h1E, 3'd1, 3'd0); // 2 = D1
        check_note(8'h26, 3'd2, 3'd0); // 3 = E1
        check_note(8'h25, 3'd3, 3'd0); // 4 = F1
        check_note(8'h2E, 3'd4, 3'd0); // 5 = G1
        check_note(8'h36, 3'd5, 3'd0); // 6 = A1
        check_note(8'h3D, 3'd6, 3'd0); // 7 = B1
        release_note(8'h3D);
        release_note(8'h16);
        release_note(8'h1E);
        release_note(8'h26);
        release_note(8'h25);
        release_note(8'h2E);
        release_note(8'h36);

        check_note(8'h15, 3'd0, 3'd1); // Q = C2
        check_note(8'h1D, 3'd1, 3'd1); // W = D2
        check_note(8'h24, 3'd2, 3'd1); // E = E2
        check_note(8'h2D, 3'd3, 3'd1); // R = F2
        check_note(8'h2C, 3'd4, 3'd1); // T = G2
        check_note(8'h35, 3'd5, 3'd1); // Y = A2
        check_note(8'h3C, 3'd6, 3'd1); // U = B2
        check_note(8'h1C, 3'd0, 3'd2); // A = C3
        check_note(8'h1B, 3'd1, 3'd2); // S = D3
        check_note(8'h23, 3'd2, 3'd2); // D = E3
        check_note(8'h2B, 3'd3, 3'd2); // F = F3
        check_note(8'h34, 3'd4, 3'd2); // G = G3
        check_note(8'h33, 3'd5, 3'd2); // H = A3
        check_note(8'h3B, 3'd6, 3'd2); // J = B3
        check_note(8'h1A, 3'd0, 3'd3); // Z = C4
        check_note(8'h22, 3'd1, 3'd3); // X = D4
        check_note(8'h21, 3'd2, 3'd3); // C = E4
        check_note(8'h2A, 3'd3, 3'd3); // V = F4
        check_note(8'h32, 3'd4, 3'd3); // B = G4
        check_note(8'h31, 3'd5, 3'd3); // N = A4
        check_note(8'h3A, 3'd6, 3'd3); // M = B4
        release_note(8'h3A);

        // Several keys can be held; releasing one must identify that exact key.
        check_note(8'h16, 3'd0, 3'd0);
        check_note(8'h1E, 3'd1, 3'd0);
        begin : stale_release
            integer off_before;
            off_before = note_off_count;
            send_byte(8'hF0);
            send_byte(8'h16);
            if (note_off_count != off_before + 1 || last_key != 8'h16 || note_down)
                $fatal(1, "release event did not identify the matching older key");
        end
        release_note(8'h1E);

        // Key-repeat make codes must not allocate duplicate logical presses.
        begin : repeat_filter
            integer on_before;
            on_before = note_on_count;
            send_byte(8'h16);
            send_byte(8'h16);
            if (note_on_count != on_before + 1)
                $fatal(1, "repeated make generated duplicate Note On events");
        end
        release_note(8'h16);

        // Keypad remains digit-only; 0/8/9 and keypad 1..7 do not select notes.
        begin : ignored_digits
            integer on_before;
            on_before = note_on_count;
            send_byte(8'h45); // 0
            send_byte(8'h3E); // 8
            send_byte(8'h46); // 9
            send_byte(8'h69); // keypad 1
            if (note_on_count != on_before || note_down)
                $fatal(1, "digit/keypad unexpectedly selected a note");
        end

        // Extended keys are ignored, even if their byte matches a keypad digit.
        send_byte(8'hE0);
        begin : check_extended
            integer count_before;
            reg [3:0] digit_before;
            count_before = valid_count;
            digit_before = digit;
            send_byte(8'h69);
            if (valid_count != count_before || digit !== digit_before)
                $fatal(1, "extended scan code unexpectedly changed digit");
        end

        $display("PASS PS/2 digits, four keyboard-row octaves, independent key releases, and repeat filtering");
        $finish;
    end
endmodule
