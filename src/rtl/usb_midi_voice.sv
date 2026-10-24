// Integration at the USB-host payload boundary, not at USB D+/D- pins.
// Supply complete 4-byte packets in clk's domain. Hold rst_n low during
// host disconnect/re-enumeration to discard pending events and silence voice.
// PCM is unsigned 16-bit, midpoint 32768; sample_ready advances the oscillator
// once per accepted sample (~48006.49 samples/s with the existing PWM clock).
module usb_midi_voice #(
    parameter [3:0] CABLE_NUMBER = 4'd0
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] packet_data,
    input wire packet_valid,
    output wire packet_ready,
    output wire packet_error,
    input wire sample_ready,
    output wire [15:0] sample,
    output wire gate,
    output wire [3:0] channel,
    output wire [6:0] note,
    output wire [6:0] velocity
);
    wire event_valid, event_on;
    wire [3:0] event_channel;
    wire [6:0] event_note, event_velocity;
    usb_midi_note_decoder #(.CABLE_NUMBER(CABLE_NUMBER)) decoder (
        .clk(clk), .rst_n(rst_n), .packet_data(packet_data),
        .packet_valid(packet_valid), .packet_ready(packet_ready),
        .event_valid(event_valid), .event_ready(1'b1), .event_on(event_on),
        .event_channel(event_channel), .event_note(event_note),
        .event_velocity(event_velocity), .packet_error(packet_error)
    );
    midi_note_state voice_state (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid),
        .event_on(event_on), .event_channel(event_channel),
        .event_note(event_note), .event_velocity(event_velocity),
        .gate(gate), .channel(channel), .note(note), .velocity(velocity)
    );
    midi_wavetable oscillator (
        .clk(clk), .rst_n(rst_n), .gate(gate), .note(note),
        .velocity(velocity), .ready(sample_ready), .sample(sample)
    );
endmodule
