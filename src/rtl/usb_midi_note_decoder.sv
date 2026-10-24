// Decode already received USB-MIDI 1.0 event packets (NOT a USB host).
// USB spec midi10.pdf, section 4: b0={cable,CIN}, b1=status, b2=note,
// b3=velocity. packet_data[7:0]=b0 (first byte on USB).
// All ports use clk; asynchronous active-low reset. One-entry elastic output:
// accept input on packet_valid && packet_ready; retain output until consumed
// on event_valid && event_ready. Back-to-back packets are supported.
module usb_midi_note_decoder #(
    parameter [3:0] CABLE_NUMBER = 4'd0
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] packet_data,
    input wire packet_valid,
    output wire packet_ready,
    output reg event_valid,
    input wire event_ready,
    output reg event_on,
    output reg [3:0] event_channel,
    output reg [6:0] event_note,
    output reg [6:0] event_velocity,
    output reg packet_error
);
    wire [3:0] cable = packet_data[7:4];
    wire [3:0] cin = packet_data[3:0];
    wire [7:0] status = packet_data[15:8];
    wire [7:0] note_byte = packet_data[23:16];
    wire [7:0] velocity_byte = packet_data[31:24];
    assign packet_ready = !event_valid || event_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            event_valid <= 0;
            event_on <= 0;
            event_channel <= 0;
            event_note <= 0;
            event_velocity <= 0;
            packet_error <= 0;
        end else begin
            packet_error <= 0;
            if (event_ready) event_valid <= 0;
            if (packet_valid && packet_ready) begin
                if (cable == CABLE_NUMBER && (cin == 4'h8 || cin == 4'h9)) begin
                    if (status[7:4] != cin || note_byte[7] || velocity_byte[7]) begin
                        packet_error <= 1;
                    end else begin
                        event_valid <= 1;
                        event_on <= cin == 4'h9 && velocity_byte != 0;
                        event_channel <= status[3:0];
                        event_note <= note_byte[6:0];
                        event_velocity <= velocity_byte[6:0];
                    end
                end
                // Ignore other cables and non-note CINs. In particular,
                // CIN=F unparsed byte streams are not implemented here.
            end
        end
    end
endmodule
