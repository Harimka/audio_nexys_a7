// Record keyboard Note On/Off events with inter-event time in audio samples.
// 64 event slots preserve up to 32 ordinary press/release note pairs.
// The event storage is a small synthesizable SystemVerilog array; no Vivado IP
// is instantiated (the FPGA tools may map it to LUT RAM or registers).
module melody_recorder #(
    parameter integer EVENT_DEPTH = 64,
    parameter integer TRACK_ID = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sample_tick,
    input  wire       record_toggle,
    input  wire       play_trigger,
    input  wire       play_stop,
    input  wire       key_event,
    input  wire       key_down,
    input  wire [7:0] key_id,
    input  wire [2:0] note_index,
    input  wire [2:0] note_octave,
    input  wire [1:0] note_waveform,
    input  wire       event_ready,
    output reg        event_valid,
    output reg        event_down,
    output reg  [7:0] event_key,
    output reg  [2:0] event_note_index,
    output reg  [2:0] event_note_octave,
    output reg  [1:0] event_waveform,
    output reg        recording,
    output reg        playing,
    output reg  [6:0] event_count,
    output reg  [4:0] preview_count,
    output reg  [79:0] preview_notes,
    output reg  [895:0] roll_matrix
);
    localparam integer PTR_BITS = (EVENT_DEPTH <= 2) ? 1 : $clog2(EVENT_DEPTH);
    localparam [6:0] DEPTH_VALUE = EVENT_DEPTH[6:0];
    // The piano roll is a 16-step viewport at 120 BPM (sixteenth-note grid).
    // This is a display resolution only; playback retains sample-accurate deltas.
    localparam [31:0] UI_STEP_SAMPLES = 32'd12000;

    (* ram_style = "registers" *) reg [31:0] delta_mem [0:EVENT_DEPTH-1];
    (* ram_style = "registers" *) reg        down_mem  [0:EVENT_DEPTH-1];
    (* ram_style = "registers" *) reg [7:0]  key_mem   [0:EVENT_DEPTH-1];
    (* ram_style = "registers" *) reg [2:0]  note_mem  [0:EVENT_DEPTH-1];
    (* ram_style = "registers" *) reg [2:0]  octave_mem[0:EVENT_DEPTH-1];
    (* ram_style = "registers" *) reg [1:0]  waveform_mem[0:EVENT_DEPTH-1];

    reg [31:0] elapsed_samples;
    reg [31:0] wait_samples;
    reg [PTR_BITS-1:0] play_index;
    reg cleanup_pending;
    reg [7:0] cleanup_index;
    reg [255:0] playback_keys_down;
    reg [2:0] playback_note [0:255];
    reg [2:0] playback_octave [0:255];
    reg [PTR_BITS-1:0] write_index;
    reg rendering;
    reg render_closing;
    reg [7:0] render_close_key;
    reg [5:0] render_close_step;
    reg render_commit_pending;
    reg [895:0] roll_build_matrix;
    reg [PTR_BITS-1:0] render_index;
    reg [31:0] render_time;
    reg [31:0] render_tail_samples;
    reg [7:0] render_key_index;
    reg [4:0] render_pitch;
    reg [4:0] render_start_step [0:255];
    reg [4:0] render_key_pitch [0:255];
    reg [255:0] render_key_active;
    reg [5:0] render_end_step;
    reg [3:0] render_cell;
    integer render_i;
    integer render_j;
    integer i;

    // Assign a unique playback identity to each mapped piano key per track.
    function [4:0] playback_key_index(input [7:0] scan_code);
        begin
            case (scan_code)
                8'h16: playback_key_index = 5'd0;
                8'h1E: playback_key_index = 5'd1;
                8'h26: playback_key_index = 5'd2;
                8'h25: playback_key_index = 5'd3;
                8'h2E: playback_key_index = 5'd4;
                8'h36: playback_key_index = 5'd5;
                8'h3D: playback_key_index = 5'd6;
                8'h15: playback_key_index = 5'd7;
                8'h1D: playback_key_index = 5'd8;
                8'h24: playback_key_index = 5'd9;
                8'h2D: playback_key_index = 5'd10;
                8'h2C: playback_key_index = 5'd11;
                8'h35: playback_key_index = 5'd12;
                8'h3C: playback_key_index = 5'd13;
                8'h1C: playback_key_index = 5'd14;
                8'h1B: playback_key_index = 5'd15;
                8'h23: playback_key_index = 5'd16;
                8'h2B: playback_key_index = 5'd17;
                8'h34: playback_key_index = 5'd18;
                8'h33: playback_key_index = 5'd19;
                8'h3B: playback_key_index = 5'd20;
                8'h1A: playback_key_index = 5'd21;
                8'h22: playback_key_index = 5'd22;
                8'h21: playback_key_index = 5'd23;
                8'h2A: playback_key_index = 5'd24;
                8'h32: playback_key_index = 5'd25;
                8'h31: playback_key_index = 5'd26;
                8'h3A: playback_key_index = 5'd27;
                default: playback_key_index = 5'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            elapsed_samples <= 32'd0;
            wait_samples <= 32'd0;
            play_index <= {PTR_BITS{1'b0}};
            write_index <= {PTR_BITS{1'b0}};
            event_valid <= 1'b0;
            event_down <= 1'b0;
            event_key <= 8'd0;
            event_note_index <= 3'd0;
            event_note_octave <= 3'd3;
            event_waveform <= 2'd0;
            event_count <= 7'd0;
            preview_count <= 5'd0;
            preview_notes <= 80'd0;
            roll_matrix <= 896'd0;
            roll_build_matrix <= 896'd0;
            recording <= 1'b0;
            playing <= 1'b0;
            cleanup_pending <= 1'b0;
            rendering <= 1'b0;
            render_closing <= 1'b0;
            render_close_key <= 8'd0;
            render_close_step <= 6'd0;
            render_commit_pending <= 1'b0;
            render_index <= {PTR_BITS{1'b0}};
            render_time <= 32'd0;
            render_tail_samples <= 32'd0;
            render_key_index <= 8'd0;
            render_pitch <= 5'd0;
            render_end_step <= 6'd0;
            render_cell <= 4'd0;
            render_key_active <= 256'd0;
            cleanup_index <= 8'd0;
            playback_keys_down <= 256'd0;
            for (i = 0; i < 256; i = i + 1) begin
                playback_note[i] <= 3'd0;
                playback_octave[i] <= 3'd3;
                render_start_step[i] <= 5'd0;
                render_key_pitch[i] <= 5'd0;
            end
        end else begin
            if (sample_tick && recording)
                elapsed_samples <= elapsed_samples + 1'b1;

            // F9 starts a fresh take or closes the current one.
            if (record_toggle) begin
                if (!recording && !playing && !cleanup_pending) begin
                    recording <= 1'b1;
                    event_count <= 7'd0;
                    preview_count <= 5'd0;
                    preview_notes <= 80'd0;
                    roll_matrix <= 896'd0;
                    roll_build_matrix <= 896'd0;
                    write_index <= {PTR_BITS{1'b0}};
                    elapsed_samples <= 32'd0;
                    render_time <= 32'd0;
                    render_key_active <= 256'd0;
                    rendering <= 1'b0;
                    render_closing <= 1'b0;
                    render_commit_pending <= 1'b0;
                end else if (recording) begin
                    recording <= 1'b0;
                    // Finalize a display projection once recording has stopped.
                    render_tail_samples <= elapsed_samples;
                    render_index <= {PTR_BITS{1'b0}};
                    render_time <= 32'd0;
                    rendering <= (event_count != 0);
                end
            end

            // Capture each physical key transition and its elapsed sample time.
            if (key_event && recording && event_count < DEPTH_VALUE) begin
                delta_mem[write_index] <= elapsed_samples;
                down_mem[write_index] <= key_down;
                key_mem[write_index] <= key_id;
                note_mem[write_index] <= note_index;
                octave_mem[write_index] <= note_octave;
                waveform_mem[write_index] <= note_waveform;
                write_index <= write_index + 1'b1;
                event_count <= event_count + 1'b1;
                if (key_down && preview_count < 5'd16) begin
                    preview_notes[preview_count * 5 +: 5] <= {note_octave[1:0], note_index};
                    preview_count <= preview_count + 1'b1;
                end
                elapsed_samples <= 32'd0;
                if (event_count == DEPTH_VALUE - 1'b1) begin
                    recording <= 1'b0;
                    render_tail_samples <= 32'd0;
                    render_index <= {PTR_BITS{1'b0}};
                    render_time <= 32'd0;
                    rendering <= 1'b1;
                    render_closing <= 1'b0;
                end
            end

            // Convert the recorded sample-delta stream into a 16-step piano roll.
            // One event is consumed per audio clock, then still-held notes are
            // closed at the stop time. Empty columns represent silence; notes
            // with overlapping intervals occupy separate pitch rows together.
            if (rendering) begin
                if (!render_closing && render_index < event_count) begin
                    render_time <= render_time + delta_mem[render_index];
                    render_key_index <= playback_key_index(key_mem[render_index]);
                    render_pitch <= octave_mem[render_index] * 5'd7 + note_mem[render_index];
                    if (down_mem[render_index]) begin
                        render_start_step[playback_key_index(key_mem[render_index])] <=
                            (render_time + delta_mem[render_index]) / UI_STEP_SAMPLES;
                        render_key_pitch[playback_key_index(key_mem[render_index])] <=
                            octave_mem[render_index] * 5'd7 + note_mem[render_index];
                        render_key_active[playback_key_index(key_mem[render_index])] <=
                            ((render_time + delta_mem[render_index]) / UI_STEP_SAMPLES) < 32;
                    end else if (render_key_active[playback_key_index(key_mem[render_index])]) begin
                        render_end_step <= (render_time + delta_mem[render_index] + UI_STEP_SAMPLES - 1'b1) / UI_STEP_SAMPLES;
                        for (render_i = 0; render_i < 32; render_i = render_i + 1) begin
                            if (render_i >= render_start_step[playback_key_index(key_mem[render_index])] &&
                                (render_i < ((render_time + delta_mem[render_index] + UI_STEP_SAMPLES - 1'b1) / UI_STEP_SAMPLES) ||
                                 render_i == render_start_step[playback_key_index(key_mem[render_index])]))
                                if (render_key_pitch[playback_key_index(key_mem[render_index])] < 28)
                                    roll_build_matrix[{render_key_pitch[playback_key_index(key_mem[render_index])], 5'b0} + render_i[4:0]] <= 1'b1;
                        end
                        render_key_active[playback_key_index(key_mem[render_index])] <= 1'b0;
                    end
                    render_index <= render_index + 1'b1;
                end else if (!render_closing) begin
                    render_closing <= 1'b1;
                    render_close_key <= 8'd0;
                    render_close_step <= 6'd0;
                    if (((render_time + render_tail_samples + UI_STEP_SAMPLES - 1'b1) / UI_STEP_SAMPLES) > 32)
                        render_end_step <= 6'd32;
                    else
                        render_end_step <= (render_time + render_tail_samples + UI_STEP_SAMPLES - 1'b1) / UI_STEP_SAMPLES;
                end else if (render_close_step < 6'd32) begin
                    if (render_key_active[render_close_key] && render_key_pitch[render_close_key] < 28 &&
                        render_close_step >= render_start_step[render_close_key] &&
                        (render_close_step < render_end_step || render_close_step == render_start_step[render_close_key]))
                        roll_build_matrix[{render_key_pitch[render_close_key], 5'b0} + render_close_step[4:0]] <= 1'b1;
                    render_close_step <= render_close_step + 1'b1;
                end else if (render_close_key == 8'hFF) begin
                    rendering <= 1'b0;
                    render_closing <= 1'b0;
                    render_commit_pending <= 1'b1;
                end else begin
                    render_close_key <= render_close_key + 1'b1;
                    render_close_step <= 6'd0;
                end
            end
            if (render_commit_pending) begin
                roll_matrix <= roll_build_matrix;
                render_commit_pending <= 1'b0;
            end

            if (play_trigger && !recording && !playing && !cleanup_pending && event_count != 0) begin
                playing <= 1'b1;
                play_index <= {PTR_BITS{1'b0}};
                wait_samples <= delta_mem[0];
                event_valid <= 1'b0;
                playback_keys_down <= 256'd0;
            end

            // A valid event is held stable until the voice allocator accepts it.
            if (event_valid && event_ready) begin
                event_valid <= 1'b0;
                if (event_down) begin
                    playback_keys_down[event_key] <= 1'b1;
                    playback_note[event_key] <= event_note_index;
                    playback_octave[event_key] <= event_note_octave;
                end else begin
                    playback_keys_down[event_key] <= 1'b0;
                end

                if (playing) begin
                    if ({1'b0, play_index} + 1'b1 >= event_count) begin
                        playing <= 1'b0;
                        cleanup_pending <= 1'b1;
                        cleanup_index <= 8'd0;
                    end else begin
                        play_index <= play_index + 1'b1;
                        wait_samples <= delta_mem[play_index + 1'b1];
                    end
                end
            end

            if (playing && !event_valid && !play_stop) begin
                if (wait_samples == 0) begin
                    event_valid <= 1'b1;
                    // High bit distinguishes playback keys from live PS/2 keys.
                    event_key <= 8'h80 + TRACK_ID * 28 + playback_key_index(key_mem[play_index]);
                    event_down <= down_mem[play_index];
                    event_note_index <= note_mem[play_index];
                    event_note_octave <= octave_mem[play_index];
                    event_waveform <= waveform_mem[play_index];
                end else if (sample_tick) begin
                    wait_samples <= wait_samples - 1'b1;
                end
            end

            // Stop/EOF releases any sequence notes that were still held.
            if (play_stop && (playing || event_valid || cleanup_pending)) begin
                playing <= 1'b0;
                event_valid <= 1'b0;
                cleanup_pending <= 1'b1;
                cleanup_index <= 8'd0;
            end else if (cleanup_pending && !event_valid) begin
                if (playback_keys_down[cleanup_index]) begin
                    event_valid <= 1'b1;
                    event_down <= 1'b0;
                    event_key <= cleanup_index[7] ? cleanup_index : (cleanup_index | 8'h80);
                    event_note_index <= playback_note[cleanup_index];
                    event_note_octave <= playback_octave[cleanup_index];
                end else if (cleanup_index == 8'hFF) begin
                    cleanup_pending <= 1'b0;
                end else begin
                    cleanup_index <= cleanup_index + 1'b1;
                end
            end else if (event_valid && event_ready && cleanup_pending && !event_down) begin
                if (cleanup_index == 8'hFF)
                    cleanup_pending <= 1'b0;
                else
                    cleanup_index <= cleanup_index + 1'b1;
            end
        end
    end
endmodule
