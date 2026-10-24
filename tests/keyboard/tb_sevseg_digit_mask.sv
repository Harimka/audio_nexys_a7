`timescale 1ns/1ps
module tb_sevseg_digit_mask;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire [6:0] segments;
    wire dp;
    wire [7:0] anodes;
    integer cycles;
    integer enabled_seen = 0;

    sevseg_ctrl #(.SCAN_DIV_BITS(2)) dut (
        .clk(clk), .arst_n(rst_n), .sevseg_32bit_hex_val(32'h00000009),
        .digit_mask(8'b00000001), .seg_active_n(segments),
        .don_active_n(dp), .anodes(anodes)
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        for (cycles = 0; cycles < 100; cycles = cycles + 1) begin
            @(posedge clk);
            #1;
            if (anodes != 8'hFF) begin
                if (anodes != 8'hFE)
                    $fatal(1, "unexpected active digit mask %02h", anodes);
                if (segments !== 7'b0011000)
                    $fatal(1, "digit zero should display 9, segment pattern=%07b", segments);
                enabled_seen = enabled_seen + 1;
            end else if (segments !== 7'b1111111) begin
                $fatal(1, "disabled digits must be blank, pattern=%07b", segments);
            end
        end
        if (enabled_seen == 0) $fatal(1, "digit zero was never enabled");
        $display("PASS seven-segment mask enables only AN[0] and blanks the other seven digits");
        $finish;
    end
endmodule
