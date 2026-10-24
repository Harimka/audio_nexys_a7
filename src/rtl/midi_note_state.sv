// One monophonic voice. Every event_valid strobe is accepted on clk.
// The latest Note On wins; only a matching note AND channel releases it.
// There is no return to an older held note. rst_n clears the active voice.
module midi_note_state (
    input wire clk,
    input wire rst_n,
    input wire event_valid,
    input wire event_on,
    input wire [3:0] event_channel,
    input wire [6:0] event_note,
    input wire [6:0] event_velocity,
    output reg gate,
    output reg [3:0] channel,
    output reg [6:0] note,
    output reg [6:0] velocity
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate <= 0;
            channel <= 0;
            note <= 0;
            velocity <= 0;
        end else if (event_valid) begin
            if (event_on && event_velocity != 0) begin
                gate <= 1;
                channel <= event_channel;
                note <= event_note;
                velocity <= event_velocity;
            end else if (gate && note == event_note && channel == event_channel) begin
                gate <= 0;
                velocity <= 0;
            end
        end
    end
endmodule
