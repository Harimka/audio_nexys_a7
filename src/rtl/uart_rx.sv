// 8-N-1 asynchronous UART receiver. Sample the start bit in its middle,
// then sample each data bit one bit period apart.
module uart_rx #(
    parameter integer CLK_HZ = 49_158_650,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
    reg [1:0] state;
    reg [15:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    reg rx_meta, rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            count     <= 0;
            bit_index <= 0;
            shift_reg <= 0;
            data      <= 0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                IDLE: if (!rx_sync) begin
                    state <= START;
                    count <= HALF_BIT - 1;
                end
                START: if (count == 0) begin
                    if (!rx_sync) begin
                        state     <= DATA;
                        count     <= CLKS_PER_BIT - 1;
                        bit_index <= 0;
                    end else state <= IDLE;
                end else count <= count - 1'b1;
                DATA: if (count == 0) begin
                    shift_reg[bit_index] <= rx_sync;
                    count <= CLKS_PER_BIT - 1;
                    if (bit_index == 3'd7) state <= STOP;
                    else bit_index <= bit_index + 1'b1;
                end else count <= count - 1'b1;
                STOP: if (count == 0) begin
                    if (rx_sync) begin
                        data  <= shift_reg;
                        valid <= 1'b1;
                    end
                    state <= IDLE;
                end else count <= count - 1'b1;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
