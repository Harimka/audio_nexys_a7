`timescale 1ns/1ps
module tb_ps2_keyboard_digit;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg ps2_clk = 1;
    reg ps2_data = 1;
    wire [3:0] digit;
    wire digit_valid;
    integer valid_count = 0;
    reg [3:0] last_digit = 0;

    ps2_keyboard_digit #(.FILTER_BITS(3), .TIMEOUT_CYCLES(2000)) dut (
        .clk(clk), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .digit(digit), .digit_valid(digit_valid)
    );

    always @(posedge clk) begin
        if (digit_valid) begin
            valid_count <= valid_count + 1;
            last_digit <= digit;
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

        $display("PASS PS/2 Set-2 top-row/keypad digits 0-9, break and extended filtering");
        $finish;
    end
endmodule
