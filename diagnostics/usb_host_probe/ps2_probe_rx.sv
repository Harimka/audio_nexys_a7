// Passive PIC24->FPGA PS/2 observer. Both pins are INPUTS, never driven.
// One clk domain, active-low asynchronous reset. Two-stage synchronization,
// FILTER_BITS consecutive equal samples, falling-edge PS/2 sampling,
// start=0, 8 data bits LSB first, odd parity, stop=1. No host commands.
module ps2_probe_rx #(
    parameter integer FILTER_BITS = 8,
    parameter integer TIMEOUT_CYCLES = 200_000 // 2 ms at 100 MHz
) (
    input wire clk, rst_n,
    input wire ps2_clk, ps2_data,
    output reg [7:0] data,
    output reg valid, frame_error, timeout_error,
    output wire clock_level, data_level,
    output wire clock_change, data_change, falling_edge
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] clk_sync, data_sync;
    reg [FILTER_BITS-1:0] clk_history, data_history;
    reg clk_filtered, data_filtered, clk_previous, data_previous;
    reg [3:0] bit_count;
    reg [7:0] shift;
    reg parity_bit;
    localparam integer TIMER_BITS = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [TIMER_BITS-1:0] age;
    assign clock_level = clk_filtered;
    assign data_level = data_filtered;
    assign clock_change = clk_previous != clk_filtered;
    assign data_change = data_previous != data_filtered;
    assign falling_edge = clk_previous && !clk_filtered;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync <= 2'b11; data_sync <= 2'b11;
            clk_history <= {FILTER_BITS{1'b1}};
            data_history <= {FILTER_BITS{1'b1}};
            clk_filtered <= 1; data_filtered <= 1;
            clk_previous <= 1; data_previous <= 1;
        end else begin
            clk_sync <= {clk_sync[0], ps2_clk};
            data_sync <= {data_sync[0], ps2_data};
            clk_history <= {clk_history[FILTER_BITS-2:0], clk_sync[1]};
            data_history <= {data_history[FILTER_BITS-2:0], data_sync[1]};
            if (&clk_history) clk_filtered <= 1;
            else if (~|clk_history) clk_filtered <= 0;
            if (&data_history) data_filtered <= 1;
            else if (~|data_history) data_filtered <= 0;
            clk_previous <= clk_filtered;
            data_previous <= data_filtered;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count <= 0; shift <= 0; parity_bit <= 0; age <= 0;
            data <= 0; valid <= 0; frame_error <= 0; timeout_error <= 0;
        end else begin
            valid <= 0; frame_error <= 0; timeout_error <= 0;
            if (falling_edge) begin
                age <= 0;
                case (bit_count)
                    0: if (!data_filtered) bit_count <= 1;
                       else frame_error <= 1;
                    1,2,3,4,5,6,7,8: begin
                        shift[bit_count-1] <= data_filtered;
                        bit_count <= bit_count + 1'b1;
                    end
                    9: begin parity_bit <= data_filtered; bit_count <= 10; end
                    10: begin
                        bit_count <= 0;
                        if (data_filtered && ((^shift) ^ parity_bit)) begin
                            data <= shift;
                            valid <= 1;
                        end else frame_error <= 1;
                    end
                    default: bit_count <= 0;
                endcase
            end else if (bit_count != 0) begin
                if (age == TIMEOUT_CYCLES-1) begin
                    bit_count <= 0; age <= 0; timeout_error <= 1;
                end else age <= age + 1'b1;
            end else age <= 0;
        end
    end
endmodule
