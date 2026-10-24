// Receive PS/2 Set-2 keyboard bytes and remember the last numeric key pressed.
// PS/2 pins are asynchronous to clk; each is synchronized and lightly filtered.
// The PIC24 on Nexys A7 translates a supported USB HID keyboard to this PS/2
// interface. This module is receive-only and never drives either pin.
module ps2_keyboard_digit #(
    parameter integer FILTER_BITS = 8,
    parameter integer TIMEOUT_CYCLES = 200_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg  [3:0] digit,
    output reg        digit_valid
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] clk_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] data_sync;
    reg [FILTER_BITS-1:0] clk_history;
    reg [FILTER_BITS-1:0] data_history;
    reg clk_filtered, data_filtered;
    reg clk_previous;

    wire falling_edge = clk_previous && !clk_filtered;

    localparam integer TIMER_BITS = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [TIMER_BITS-1:0] age;
    reg [3:0] bit_count;
    reg [7:0] shift;
    reg parity_bit;
    reg byte_valid;
    reg [7:0] byte_data;
    reg break_prefix;
    reg extended_prefix;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync      <= 2'b11;
            data_sync     <= 2'b11;
            clk_history   <= {FILTER_BITS{1'b1}};
            data_history  <= {FILTER_BITS{1'b1}};
            clk_filtered  <= 1'b1;
            data_filtered <= 1'b1;
            clk_previous  <= 1'b1;
        end else begin
            clk_sync     <= {clk_sync[0], ps2_clk};
            data_sync    <= {data_sync[0], ps2_data};
            clk_history  <= {clk_history[FILTER_BITS-2:0], clk_sync[1]};
            data_history <= {data_history[FILTER_BITS-2:0], data_sync[1]};

            if (&clk_history) clk_filtered <= 1'b1;
            else if (~|clk_history) clk_filtered <= 1'b0;
            if (&data_history) data_filtered <= 1'b1;
            else if (~|data_history) data_filtered <= 1'b0;

            clk_previous <= clk_filtered;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            age           <= 0;
            bit_count     <= 0;
            shift         <= 0;
            parity_bit    <= 0;
            byte_valid    <= 1'b0;
            byte_data     <= 0;
            break_prefix  <= 1'b0;
            extended_prefix <= 1'b0;
            digit         <= 0;
            digit_valid   <= 1'b0;
        end else begin
            byte_valid  <= 1'b0;
            digit_valid <= 1'b0;

            if (falling_edge) begin
                age <= 0;
                case (bit_count)
                    0: begin
                        if (!data_filtered) bit_count <= 1;
                    end
                    1,2,3,4,5,6,7,8: begin
                        shift[bit_count-1] <= data_filtered;
                        bit_count <= bit_count + 1'b1;
                    end
                    9: begin
                        parity_bit <= data_filtered;
                        bit_count <= 10;
                    end
                    10: begin
                        bit_count <= 0;
                        if (data_filtered && ((^shift) ^ parity_bit)) begin
                            byte_data  <= shift;
                            byte_valid <= 1'b1;
                        end
                    end
                    default: bit_count <= 0;
                endcase
            end else if (bit_count != 0) begin
                if (age == TIMEOUT_CYCLES-1) begin
                    bit_count <= 0;
                    age <= 0;
                end else begin
                    age <= age + 1'b1;
                end
            end else begin
                age <= 0;
            end

            if (byte_valid) begin
                if (byte_data == 8'hF0) begin
                    break_prefix <= 1'b1;
                end else if (byte_data == 8'hE0) begin
                    extended_prefix <= 1'b1;
                end else begin
                    if (!break_prefix && !extended_prefix) begin
                        case (byte_data)
                            // Number row, PS/2 Set 2.
                            8'h16: begin digit <= 4'd1; digit_valid <= 1'b1; end
                            8'h1E: begin digit <= 4'd2; digit_valid <= 1'b1; end
                            8'h26: begin digit <= 4'd3; digit_valid <= 1'b1; end
                            8'h25: begin digit <= 4'd4; digit_valid <= 1'b1; end
                            8'h2E: begin digit <= 4'd5; digit_valid <= 1'b1; end
                            8'h36: begin digit <= 4'd6; digit_valid <= 1'b1; end
                            8'h3D: begin digit <= 4'd7; digit_valid <= 1'b1; end
                            8'h3E: begin digit <= 4'd8; digit_valid <= 1'b1; end
                            8'h46: begin digit <= 4'd9; digit_valid <= 1'b1; end
                            8'h45: begin digit <= 4'd0; digit_valid <= 1'b1; end

                            // Numeric keypad, PS/2 Set 2.
                            8'h70: begin digit <= 4'd0; digit_valid <= 1'b1; end
                            8'h69: begin digit <= 4'd1; digit_valid <= 1'b1; end
                            8'h72: begin digit <= 4'd2; digit_valid <= 1'b1; end
                            8'h7A: begin digit <= 4'd3; digit_valid <= 1'b1; end
                            8'h6B: begin digit <= 4'd4; digit_valid <= 1'b1; end
                            8'h73: begin digit <= 4'd5; digit_valid <= 1'b1; end
                            8'h74: begin digit <= 4'd6; digit_valid <= 1'b1; end
                            8'h6C: begin digit <= 4'd7; digit_valid <= 1'b1; end
                            8'h75: begin digit <= 4'd8; digit_valid <= 1'b1; end
                            8'h7D: begin digit <= 4'd9; digit_valid <= 1'b1; end
                            default: ;
                        endcase
                    end
                    break_prefix    <= 1'b0;
                    extended_prefix <= 1'b0;
                end
            end
        end
    end
endmodule
