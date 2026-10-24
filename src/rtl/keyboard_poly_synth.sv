// Eight-voice, monophonic-per-keyboard-key DDS mixer for PS/2 note events.
// Each active key has its own phase accumulator, so held notes form chords.
module keyboard_poly_synth #(
    parameter integer VOICES = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        note_event,
    input  wire        note_down,
    input  wire [7:0]  note_key,
    input  wire [2:0]  note_index,
    input  wire [2:0]  note_octave,
    input  wire [1:0]  note_waveform,
    input  wire        ready,
    output reg  [15:0] sample,
    output reg  [3:0]  active_count
);
    localparam [31:0] INC_C4 = 32'h01652AB0;
    localparam [31:0] INC_D4 = 32'h0190E48F;
    localparam [31:0] INC_E4 = 32'h01C1FF63;
    localparam [31:0] INC_F4 = 32'h01DCC136;
    localparam [31:0] INC_G4 = 32'h02172483;
    localparam [31:0] INC_A4 = 32'h0258AB98;
    localparam [31:0] INC_B4 = 32'h02A239A0;

    reg [VOICES-1:0] active;
    reg [7:0] key_id [0:VOICES-1];
    reg [2:0] note_id [0:VOICES-1];
    reg [2:0] octave_id [0:VOICES-1];
    reg [1:0] waveform_id [0:VOICES-1];
    reg [31:0] phase [0:VOICES-1];
    wire [15:0] voice_wave [0:VOICES-1];
    reg [31:0] base_increment;
    reg [31:0] increment;
    reg signed [19:0] mix_sum;
    reg signed [19:0] scaled_mix;
    reg [2:0] mix_shift;
    integer i;
    integer selected_voice;

    genvar wave_i;
    generate
        for (wave_i = 0; wave_i < VOICES; wave_i = wave_i + 1) begin : waveform_per_voice
            waveform_lookup wave_lookup (
                .phase(phase[wave_i]),
                .waveform_select(waveform_id[wave_i]),
                .sample(voice_wave[wave_i])
            );
        end
    endgenerate

    always @* begin
        base_increment = INC_C4;
        case (note_index)
            3'd0: base_increment = INC_C4;
            3'd1: base_increment = INC_D4;
            3'd2: base_increment = INC_E4;
            3'd3: base_increment = INC_F4;
            3'd4: base_increment = INC_G4;
            3'd5: base_increment = INC_A4;
            3'd6: base_increment = INC_B4;
            default: base_increment = INC_C4;
        endcase
        case (note_octave)
            3'd0: increment = base_increment >> 3;
            3'd1: increment = base_increment >> 2;
            3'd2: increment = base_increment >> 1;
            3'd3: increment = base_increment;
            3'd4: increment = base_increment << 1;
            3'd5: increment = base_increment << 2;
            3'd6: increment = base_increment << 3;
            3'd7: increment = base_increment << 4;
            default: increment = base_increment;
        endcase
    end

    // Allocate the first free voice on make; release only the matching key.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= {VOICES{1'b0}};
            for (i = 0; i < VOICES; i = i + 1) begin
                key_id[i] <= 8'h00;
                note_id[i] <= 3'd0;
                octave_id[i] <= 3'd3;
                waveform_id[i] <= 2'd0;
                phase[i] <= 32'd0;
            end
        end else begin
            if (ready) begin
                for (i = 0; i < VOICES; i = i + 1) begin
                    if (active[i])
                        phase[i] <= phase[i] + voice_increment(note_id[i], octave_id[i]);
                end
            end

            if (note_event) begin
                selected_voice = -1;
                if (note_down) begin
                    for (i = 0; i < VOICES; i = i + 1) begin
                        if (active[i] && key_id[i] == note_key)
                            selected_voice = i;
                    end
                    if (selected_voice < 0) begin
                        for (i = 0; i < VOICES; i = i + 1) begin
                            if (!active[i] && selected_voice < 0)
                                selected_voice = i;
                        end
                    end
                    if (selected_voice >= 0) begin
                        active[selected_voice] <= 1'b1;
                        key_id[selected_voice] <= note_key;
                        note_id[selected_voice] <= note_index;
                        octave_id[selected_voice] <= note_octave;
                        waveform_id[selected_voice] <= note_waveform;
                        phase[selected_voice] <= 32'd0;
                    end
                end else begin
                    for (i = 0; i < VOICES; i = i + 1) begin
                        if (active[i] && key_id[i] == note_key)
                            active[i] <= 1'b0;
                    end
                end
            end
        end
    end

    function [31:0] voice_increment;
        input [2:0] n;
        input [2:0] o;
        reg [31:0] b;
        begin
            case (n)
                3'd0: b = INC_C4;
                3'd1: b = INC_D4;
                3'd2: b = INC_E4;
                3'd3: b = INC_F4;
                3'd4: b = INC_G4;
                3'd5: b = INC_A4;
                3'd6: b = INC_B4;
                default: b = INC_C4;
            endcase
            case (o)
                3'd0: voice_increment = b >> 3;
                3'd1: voice_increment = b >> 2;
                3'd2: voice_increment = b >> 1;
                3'd3: voice_increment = b;
                3'd4: voice_increment = b << 1;
                3'd5: voice_increment = b << 2;
                3'd6: voice_increment = b << 3;
                3'd7: voice_increment = b << 4;
                default: voice_increment = b;
            endcase
        end
    endfunction

    // Mix centered waveform samples and normalize by a power-of-two voice bucket.
    // This keeps three-note chords clear while leaving headroom for eight keys.
    always @* begin
        mix_sum = 20'sd0;
        active_count = 4'd0;
        mix_shift = 3'd0;
        scaled_mix = 20'sd0;
        for (integer j = 0; j < VOICES; j = j + 1) begin
            if (active[j]) begin
                active_count = active_count + 1'b1;
                mix_sum = mix_sum + $signed({4'b0000, voice_wave[j]}) - 20'sd32768;
            end
        end

        if (active_count == 0) begin
            sample = 16'd32768;
        end else begin
            if (active_count == 1) mix_shift = 3'd0;
            else if (active_count == 2) mix_shift = 3'd1;
            else if (active_count <= 4) mix_shift = 3'd2;
            else mix_shift = 3'd3;
            scaled_mix = mix_sum >>> mix_shift;
            if (scaled_mix > 20'sd32767) sample = 16'hFFFF;
            else if (scaled_mix < -20'sd32768) sample = 16'h0000;
            else sample = scaled_mix[15:0] + 16'd32768;
        end
    end
endmodule
