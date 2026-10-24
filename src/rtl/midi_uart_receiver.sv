// UART transport wrapper. This is not a receiver for the board's USB HOST.
// All internal events use clk; the UART pin is synchronized by uart_rx.
module midi_uart_receiver #(
    parameter integer CLK_HZ = 49_158_650,
    parameter integer BAUD   = 115_200
) (
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire gate,
    output wire [6:0] note,
    output wire [6:0] velocity
);
    wire [7:0] rx_data;
    wire rx_valid, event_valid, event_on;
    wire [3:0] event_channel;
    wire [6:0] event_note, event_velocity;
    wire [3:0] active_channel;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart_receiver (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data), .valid(rx_valid)
    );
    midi_note_decoder decoder (
        .clk(clk), .rst_n(rst_n), .byte_data(rx_data), .byte_valid(rx_valid),
        .event_valid(event_valid), .event_on(event_on),
        .event_channel(event_channel), .event_note(event_note),
        .event_velocity(event_velocity)
    );
    midi_note_state voice_state (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid),
        .event_on(event_on), .event_channel(event_channel),
        .event_note(event_note), .event_velocity(event_velocity),
        .gate(gate), .channel(active_channel), .note(note), .velocity(velocity)
    );
endmodule
