// Accepts MIDI Note On/Off messages over a 115200-8-N-1 UART link.
// Supports channel voice running status for Note On/Off. One voice is active:
// the newest Note On replaces it; Note Off silences it when it matches.
module midi_uart_receiver #(
    parameter integer CLK_HZ = 49_158_650,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg        gate,
    output reg  [6:0] note,
    output reg  [6:0] velocity
);
    wire [7:0] rx_data;
    wire rx_valid;
    reg [1:0] byte_state;
    reg note_on_status;
    reg [6:0] pending_note;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart_receiver (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data), .valid(rx_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_state   <= 0;
            note_on_status <= 1'b0;
            pending_note <= 0;
            note         <= 0;
            velocity     <= 0;
            gate         <= 1'b0;
        end else if (rx_valid) begin
            if (rx_data[7]) begin
                // Ignore real-time bytes without disturbing a running message.
                if (rx_data >= 8'hF8) begin
                    byte_state <= byte_state;
                end else if ((rx_data[7:4] == 4'h8) || (rx_data[7:4] == 4'h9)) begin
                    note_on_status <= (rx_data[7:4] == 4'h9);
                    byte_state <= 1;
                end else begin
                    byte_state <= 0;
                end
            end else if (byte_state == 1) begin
                pending_note <= rx_data[6:0];
                byte_state <= 2;
            end else if (byte_state == 2) begin
                if (note_on_status && (rx_data[6:0] != 0)) begin
                    note <= pending_note;
                    velocity <= rx_data[6:0];
                    gate <= 1'b1;
                end else if (gate && (note == pending_note)) begin
                    gate <= 1'b0;
                    velocity <= 0;
                end
                // Keep the running status for the next pair of data bytes.
                byte_state <= 1;
            end
        end
    end
endmodule
