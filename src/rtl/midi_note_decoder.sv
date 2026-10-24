// MIDI 1.0 byte-stream -> note events, independent of the physical transport.
// All ports use clk. rst_n asynchronously asserts reset. byte_valid and
// event_valid are one-cycle strobes; the downstream consumer must accept every
// event. Output fields remain stable between events. Channel is zero-based.
module midi_note_decoder (
    input wire clk,
    input wire rst_n,
    input wire [7:0] byte_data,
    input wire byte_valid,
    output reg event_valid,
    output reg event_on,
    output reg [3:0] event_channel,
    output reg [6:0] event_note,
    output reg [6:0] event_velocity
);
    reg [7:0] status;
    reg have_note;
    reg [6:0] pending_note;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status <= 0;
            have_note <= 0;
            pending_note <= 0;
            event_valid <= 0;
            event_on <= 0;
            event_channel <= 0;
            event_note <= 0;
            event_velocity <= 0;
        end else begin
            event_valid <= 0;
            if (byte_valid) begin
                if (byte_data >= 8'hF8) begin
                    // Interleaved real-time bytes do not cancel running status.
                end else if (byte_data[7]) begin
                    have_note <= 0;
                    if (byte_data[7:4] == 4'h8 || byte_data[7:4] == 4'h9)
                        status <= byte_data;
                    else
                        // Other channel messages, SysEx and system-common
                        // cancel our note-message assembly (no stale data).
                        status <= 0;
                end else if (status != 0) begin
                    if (!have_note) begin
                        pending_note <= byte_data[6:0];
                        have_note <= 1;
                    end else begin
                        event_valid <= 1;
                        event_on <= status[7:4] == 4'h9 && byte_data != 0;
                        event_channel <= status[3:0];
                        event_note <= pending_note;
                        event_velocity <= byte_data[6:0];
                        have_note <= 0;
                    end
                end
            end
        end
    end
endmodule
