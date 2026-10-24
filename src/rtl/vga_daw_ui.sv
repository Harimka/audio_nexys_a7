// 800x600 FPGA DAW Workstation User Interface.
// Implements:
// 1. Warm retro light theme (12'hFEA bg, 12'hFFF cards, 12'h111 ink text, 12'h06F accent).
// 2. 28-pitch Piano-Roll (C1..B4 across 4 full octaves, exactly 16 px per row).
// 3. 16-step timeline with 8-step window shifting (steps 01..16 -> 09..24).
// 4. Red Playhead line running across timeline and auto-shifting with window.
// 5. Compact wave selector buttons (SINE, TRI, SQR, SAW).
// 6. Large live audio oscilloscope with reticle grid and CRT screen.
// 7. 4-Track sequencer matrix with live event counters (E:XX/40) and REC/PLAY status.
// 8. 16-level volume meter bar.
// 9. Footer with keyboard shortcut reference.
module vga_daw_ui (
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire [10:0] h_coord,
    input  wire [9:0]  v_coord,
    input  wire [1:0]  waveform_select,
    input  wire [1:0]  selected_track,
    input  wire [3:0]  volume,
    input  wire        audio_play,
    input  wire [3:0]  recording,
    input  wire [3:0]  playing,
    input  wire [27:0] event_counts,
    input  wire [19:0] preview_counts,
    input  wire [319:0] preview_notes,
    input  wire [447:0] roll_matrix,
    input  wire        active_note_valid,
    input  wire [2:0]  active_note,
    input  wire [1:0]  active_octave,
    output reg  [3:0]  red,
    output reg  [3:0]  green,
    output reg  [3:0]  blue
);

    // RGB444 light palette definitions
    localparam [11:0] COLOR_BG          = 12'hFEA; // Warm retro cream
    localparam [11:0] COLOR_PANEL       = 12'hFFF; // Clean white card
    localparam [11:0] COLOR_INK         = 12'h111; // Dark charcoal ink
    localparam [11:0] COLOR_DIM         = 12'h777; // Muted gray text
    localparam [11:0] COLOR_ACCENT      = 12'h06F; // Vivid DAW blue
    localparam [11:0] COLOR_ALERT       = 12'hF33; // Bright red (REC & Playhead)
    localparam [11:0] COLOR_PLAY        = 12'h094; // Forest green
    localparam [11:0] COLOR_GRID        = 12'hDDC; // Light cream grid lines
    localparam [11:0] COLOR_C_ROOT      = 12'hEFF; // Soft cyan tint for C root rows
    localparam [11:0] COLOR_SCOPE_BG    = 12'h012; // Dark scope CRT background
    localparam [11:0] COLOR_SCOPE_GRID  = 12'h034; // Faint cyan reticle grid
    localparam [11:0] COLOR_SCOPE_TRACE = 12'h0F9; // Neon green/cyan trace

    // Playhead and window shift timing (0.25 s per step @ 39.941 MHz)
    localparam [23:0] STEP_TICKS = 24'd9_985_249;
    reg [23:0] playhead_timer;
    reg [4:0]  playhead_step; // 0..23 (supports up to 24 steps = 6s before wrap)
    wire       playhead_active;

    assign playhead_active = (|recording) || (|playing) || audio_play;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            playhead_timer <= 24'd0;
            playhead_step  <= 5'd0;
        end else if (playhead_active) begin
            if (playhead_timer >= STEP_TICKS) begin
                playhead_timer <= 24'd0;
                if (playhead_step >= 5'd23)
                    playhead_step <= 5'd0;
                else
                    playhead_step <= playhead_step + 1'b1;
            end else begin
                playhead_timer <= playhead_timer + 1'b1;
            end
        end else begin
            playhead_timer <= 24'd0;
            playhead_step  <= 5'd0;
        end
    end

    // 8-step window shift logic:
    // Steps 0..15 -> window_offset = 0 (displays steps 1..16)
    // Steps 16..23 -> window_offset = 8 (displays steps 9..24)
    wire [4:0] window_offset;
    wire [3:0] visible_step;
    wire [10:0] playhead_x;

    assign window_offset = (playhead_step >= 5'd16) ? 5'd8 : 5'd0;
    assign visible_step  = (playhead_step >= 5'd16) ? (playhead_step[3:0] - 4'd8) : playhead_step[3:0];
    assign playhead_x    = 11'd68 + visible_step * 11'd28;

    // REC blinking marker generator
    reg [23:0] blink_timer;
    reg        rec_blink;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_timer <= 24'd0;
            rec_blink   <= 1'b0;
        end else if (blink_timer >= 24'd9_999_999) begin
            blink_timer <= 24'd0;
            rec_blink   <= ~rec_blink;
        end else begin
            blink_timer <= blink_timer + 1'b1;
        end
    end

    // Pitch mapping for active live note input
    wire [4:0] current_active_pitch = {3'b0, active_octave} * 5'd7 + {2'b0, active_note};

    // Waveform generator for live oscilloscope
    reg [10:0] wave_x_offset;
    wire [7:0] wave_phase_addr;
    wire [31:0] wave_phase;
    wire [15:0] wave_sample;
    wire signed [16:0] wave_centered;
    integer wave_curve_y;

    always_comb begin
        wave_x_offset = (h_coord >= 11'd544 && h_coord < 11'd778) ? (h_coord - 11'd544) : 11'd0;
    end

    // Map 234 pixels to ~2 full cycles of the wave
    assign wave_phase_addr = (wave_x_offset[7:0] << 1) + (wave_x_offset[7:0] >> 2);
    assign wave_phase = {wave_phase_addr, 24'b0};

    waveform_lookup wave_inst (
        .phase           ( wave_phase      ),
        .waveform_select ( waveform_select ),
        .sample          ( wave_sample     )
    );

    assign wave_centered = $signed({1'b0, wave_sample}) - 17'sd32768;

    always_comb begin
        // Oscilloscope center line at Y=210, peak amplitude ~64 px
        wave_curve_y = 210 - ($signed(wave_centered) >>> 9);
    end

    // Functions for text representation
    function automatic [7:0] hex_digit(input [3:0] val);
        begin
            hex_digit = (val < 4'd10) ? (8'h30 + val) : (8'h41 + val - 4'd10);
        end
    endfunction

    function automatic [7:0] dec_digit(input [4:0] val);
        begin
            dec_digit = 8'h30 + (val % 10);
        end
    endfunction

    wire [6:0] trk0_count = event_counts[6:0];
    wire [6:0] trk1_count = event_counts[13:7];
    wire [6:0] trk2_count = event_counts[20:14];
    wire [6:0] trk3_count = event_counts[27:21];

    function automatic [6:0] track_evt_count(input [1:0] trk);
        begin
            case (trk)
                2'd0: track_evt_count = trk0_count;
                2'd1: track_evt_count = trk1_count;
                2'd2: track_evt_count = trk2_count;
                default: track_evt_count = trk3_count;
            endcase
        end
    endfunction

    function automatic [7:0] pitch_char(input [2:0] p);
        begin
            case (p)
                3'd0: pitch_char = "C";
                3'd1: pitch_char = "D";
                3'd2: pitch_char = "E";
                3'd3: pitch_char = "F";
                3'd4: pitch_char = "G";
                3'd5: pitch_char = "A";
                default: pitch_char = "B";
            endcase
        end
    endfunction

    // Unified text engine signals
    reg        in_text;
    reg  [7:0] char_code;
    reg  [2:0] char_row;
    reg  [2:0] char_col;
    reg [11:0] char_color;
    wire [7:0] glyph_bits;
    wire       text_pixel;

    font_rom ui_font_rom (
        .char_code ( char_code  ),
        .row       ( char_row   ),
        .bits      ( glyph_bits )
    );

    assign text_pixel = in_text ? glyph_bits[3'd7 - char_col] : 1'b0;

    // Combinational text coordinate decoder
    integer text_x, text_y;
    reg [1:0]  track_row_id;
    reg [6:0]  curr_track_count;
    reg [4:0]  disp_step_num;
    reg [4:0]  grid_pitch;
    reg [2:0]  grid_note_idx;
    reg [2:0]  grid_octave;

    always_comb begin
        in_text     = 1'b0;
        char_code   = 8'h20;
        char_row    = 3'd0;
        char_col    = 3'd0;
        char_color  = COLOR_INK;

        // -------------------------------------------------------------
        // 1. Header Text
        // -------------------------------------------------------------
        // Title: "NEXYS A7 // FPGA 4-TRACK DAW" (2X scale) at X=16, Y=12
        if (v_coord >= 10'd12 && v_coord < 10'd28 && h_coord >= 11'd16 && h_coord < 11'd464) begin
            in_text    = 1'b1;
            char_row   = (v_coord - 10'd12) >> 1;
            char_col   = ((h_coord - 11'd16) >> 1) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd16) >> 4)
                0: char_code = "N"; 1: char_code = "E"; 2: char_code = "X"; 3: char_code = "Y"; 4: char_code = "S";
                5: char_code = " "; 6: char_code = "A"; 7: char_code = "7"; 8: char_code = " "; 9: char_code = "/";
                10: char_code = "/"; 11: char_code = " "; 12: char_code = "F"; 13: char_code = "P"; 14: char_code = "G";
                15: char_code = "A"; 16: char_code = " "; 17: char_code = "4"; 18: char_code = "-"; 19: char_code = "T";
                20: char_code = "R"; 21: char_code = "A"; 22: char_code = "C"; 23: char_code = "K"; 24: char_code = " ";
                25: char_code = "D"; 26: char_code = "A"; 27: char_code = "W";
                default: char_code = " ";
            endcase
        end
        // "REC" text at X=594, Y=17 (1X)
        else if (v_coord >= 10'd17 && v_coord < 10'd25 && h_coord >= 11'd594 && h_coord < 11'd618) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd17;
            char_col   = (h_coord - 11'd594) & 3'b111;
            char_color = COLOR_ALERT;
            case ((h_coord - 11'd594) >> 3)
                0: char_code = "R"; 1: char_code = "E"; 2: char_code = "C";
                default: char_code = " ";
            endcase
        end
        // Status Badge at X=654, Y=15 (1X)
        else if (v_coord >= 10'd15 && v_coord < 10'd23 && h_coord >= 11'd654 && h_coord < 11'd686) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd15;
            char_col   = (h_coord - 11'd654) & 3'b111;
            char_color = COLOR_PANEL; // White text on badge
            if (|playing) begin
                case ((h_coord - 11'd654) >> 3)
                    0: char_code = "P"; 1: char_code = "L"; 2: char_code = "A"; 3: char_code = "Y";
                    default: char_code = " ";
                endcase
            end else if (audio_play) begin
                case ((h_coord - 11'd654) >> 3)
                    0: char_code = "L"; 1: char_code = "I"; 2: char_code = "V"; 3: char_code = "E";
                    default: char_code = " ";
                endcase
            end else begin
                case ((h_coord - 11'd654) >> 3)
                    0: char_code = "I"; 1: char_code = "D"; 2: char_code = "L"; 3: char_code = "E";
                    default: char_code = " ";
                endcase
            end
        end
        // "TRK: 1" at X=720, Y=17 (1X)
        else if (v_coord >= 10'd17 && v_coord < 10'd25 && h_coord >= 11'd720 && h_coord < 11'd768) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd17;
            char_col   = (h_coord - 11'd720) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd720) >> 3)
                0: char_code = "T"; 1: char_code = "R"; 2: char_code = "K"; 3: char_code = ":";
                4: char_code = " "; 5: char_code = 8'h31 + selected_track;
                default: char_code = " ";
            endcase
        end

        // -------------------------------------------------------------
        // 2. Piano Roll Header & Timeline
        // -------------------------------------------------------------
        // Title at X=22, Y=51 (1X)
        else if (v_coord >= 10'd51 && v_coord < 10'd59 && h_coord >= 11'd22 && h_coord < 11'd366) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd51;
            char_col   = (h_coord - 11'd22) & 3'b111;
            char_color = COLOR_INK;
            // Title shows active window offset (01..16 or 09..24)
            case ((h_coord - 11'd22) >> 3)
                0: char_code = "P"; 1: char_code = "I"; 2: char_code = "A"; 3: char_code = "N"; 4: char_code = "O";
                5: char_code = " "; 6: char_code = "R"; 7: char_code = "O"; 8: char_code = "L"; 9: char_code = "L";
                10: char_code = " "; 11: char_code = "("; 12: char_code = "S"; 13: char_code = "T"; 14: char_code = "E";
                15: char_code = "P"; 16: char_code = "S"; 17: char_code = " ";
                18: char_code = (window_offset == 0) ? "0" : "0";
                19: char_code = (window_offset == 0) ? "1" : "9";
                20: char_code = "."; 21: char_code = ".";
                22: char_code = (window_offset == 0) ? "1" : "2";
                23: char_code = (window_offset == 0) ? "6" : "4";
                24: char_code = " "; 25: char_code = "/"; 26: char_code = " "; 27: char_code = "4"; 28: char_code = " ";
                29: char_code = "O"; 30: char_code = "C"; 31: char_code = "T"; 32: char_code = " "; 33: char_code = "C";
                34: char_code = "1"; 35: char_code = "."; 36: char_code = "."; 37: char_code = "B"; 38: char_code = "4";
                39: char_code = ")";
                default: char_code = " ";
            endcase
        end
        // Timeline 16 step numbers at Y=72..79, X=74 + s*28
        else if (v_coord >= 10'd72 && v_coord < 10'd80 && h_coord >= 11'd68 && h_coord < 11'd516) begin
            text_x = (h_coord - 11'd68) % 28;
            if (text_x >= 6 && text_x < 22) begin
                in_text    = 1'b1;
                char_row   = v_coord - 10'd72;
                char_col   = (text_x - 6) & 3'b111;
                disp_step_num = window_offset + ((h_coord - 11'd68) / 28) + 1;
                char_color = (((h_coord - 11'd68) / 28) % 4 == 0) ? COLOR_ACCENT : COLOR_DIM;
                if ((text_x - 6) < 8)
                    char_code = (disp_step_num >= 20) ? "2" : ((disp_step_num >= 10) ? "1" : "0");
                else
                    char_code = dec_digit(disp_step_num);
            end
        end

        // -------------------------------------------------------------
        // 3. Piano Roll 28 Key Labels (C1..B4)
        // -------------------------------------------------------------
        // Rows: Y=92..539, 28 rows x 16 px. Key tags at X=26..42
        else if (v_coord >= 10'd92 && v_coord < 10'd540 && h_coord >= 11'd26 && h_coord < 11'd50) begin
            text_y = (v_coord - 10'd92) % 16;
            if (text_y >= 4 && text_y < 12) begin
                in_text    = 1'b1;
                char_row   = text_y - 4;
                char_col   = (h_coord - 11'd26) & 3'b111;
                grid_pitch = 5'd27 - ((v_coord - 10'd92) >> 4); // 0=C1, 27=B4
                grid_note_idx = grid_pitch % 7;
                grid_octave   = grid_pitch / 7 + 1;
                if (active_note_valid && (grid_pitch == current_active_pitch))
                    char_color = COLOR_PANEL;
                else
                    char_color = (grid_note_idx == 0) ? COLOR_PANEL : COLOR_INK; // White text on blue for C
                if (h_coord < 11'd34)
                    char_code = pitch_char(grid_note_idx);
                else if (h_coord >= 11'd42 && h_coord < 11'd50)
                    char_code = 8'h30 + grid_octave;
                else
                    char_code = " ";
            end
        end

        // -------------------------------------------------------------
        // 4. Wave Selector (Compact)
        // -------------------------------------------------------------
        // Title at X=544, Y=51 (1X)
        else if (v_coord >= 10'd51 && v_coord < 10'd59 && h_coord >= 11'd544 && h_coord < 11'd632) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd51;
            char_col   = (h_coord - 11'd544) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd544) >> 3)
                0: char_code = "W"; 1: char_code = "A"; 2: char_code = "V"; 3: char_code = "E";
                4: char_code = " "; 5: char_code = "S"; 6: char_code = "E"; 7: char_code = "L";
                8: char_code = "E"; 9: char_code = "C"; 10: char_code = "T";
                default: char_code = " ";
            endcase
        end
        // 4 Button labels at Y=72..79
        else if (v_coord >= 10'd72 && v_coord < 10'd80 && h_coord >= 11'd542 && h_coord < 11'd778) begin
            text_x = (h_coord - 11'd542) % 59;
            if (text_x >= 11 && text_x < 43) begin
                in_text    = 1'b1;
                char_row   = v_coord - 10'd72;
                char_col   = (text_x - 11) & 3'b111;
                char_color = (((h_coord - 11'd542) / 59) == waveform_select) ? COLOR_PANEL : COLOR_INK;
                case ((h_coord - 11'd542) / 59)
                    0: case ((text_x - 11) >> 3) 0: char_code="S"; 1: char_code="I"; 2: char_code="N"; 3: char_code="E"; default: char_code=" "; endcase
                    1: case ((text_x - 11) >> 3) 0: char_code="T"; 1: char_code="R"; 2: char_code="I"; 3: char_code=" "; default: char_code=" "; endcase
                    2: case ((text_x - 11) >> 3) 0: char_code="S"; 1: char_code="Q"; 2: char_code="R"; 3: char_code=" "; default: char_code=" "; endcase
                    default: case ((text_x - 11) >> 3) 0: char_code="S"; 1: char_code="A"; 2: char_code="W"; 3: char_code=" "; default: char_code=" "; endcase
                endcase
            end
        end

        // -------------------------------------------------------------
        // 5. Live Oscilloscope
        // -------------------------------------------------------------
        // Title at X=544, Y=99 (1X)
        else if (v_coord >= 10'd99 && v_coord < 10'd107 && h_coord >= 11'd544 && h_coord < 11'd728) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd99;
            char_col   = (h_coord - 11'd544) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd544) >> 3)
                0: char_code = "L"; 1: char_code = "I"; 2: char_code = "V"; 3: char_code = "E"; 4: char_code = " ";
                5: char_code = "O"; 6: char_code = "S"; 7: char_code = "C"; 8: char_code = "I"; 9: char_code = "L";
                10: char_code = "L"; 11: char_code = "O"; 12: char_code = "S"; 13: char_code = "C"; 14: char_code = "O";
                15: char_code = "P"; 16: char_code = "E";
                default: char_code = " ";
            endcase
        end
        // Scope status: "VOICES: 1/8" at X=552, Y=122
        else if (v_coord >= 10'd122 && v_coord < 10'd130 && h_coord >= 11'd552 && h_coord < 11'd640) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd122;
            char_col   = (h_coord - 11'd552) & 3'b111;
            char_color = COLOR_SCOPE_TRACE;
            case ((h_coord - 11'd552) >> 3)
                0: char_code = "V"; 1: char_code = "O"; 2: char_code = "I"; 3: char_code = "C"; 4: char_code = "E";
                5: char_code = "S"; 6: char_code = ":"; 7: char_code = " ";
                8: char_code = audio_play ? "1" : "0"; 9: char_code = "/"; 10: char_code = "8";
                default: char_code = " ";
            endcase
        end
        // Scope status: "TRIG: AUTO" at X=700, Y=122
        else if (v_coord >= 10'd122 && v_coord < 10'd130 && h_coord >= 11'd700 && h_coord < 11'd780) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd122;
            char_col   = (h_coord - 11'd700) & 3'b111;
            char_color = COLOR_DIM;
            case ((h_coord - 11'd700) >> 3)
                0: char_code = "T"; 1: char_code = "R"; 2: char_code = "I"; 3: char_code = "G";
                4: char_code = ":"; 5: char_code = " "; 6: char_code = "A"; 7: char_code = "U";
                8: char_code = "T"; 9: char_code = "O";
                default: char_code = " ";
            endcase
        end

        // -------------------------------------------------------------
        // 6. 4-Track Sequencer Matrix
        // -------------------------------------------------------------
        // Title at X=544, Y=323 (1X)
        else if (v_coord >= 10'd323 && v_coord < 10'd331 && h_coord >= 11'd544 && h_coord < 11'd776) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd323;
            char_col   = (h_coord - 11'd544) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd544) >> 3)
                0: char_code = "T"; 1: char_code = "R"; 2: char_code = "A"; 3: char_code = "C"; 4: char_code = "K";
                5: char_code = " "; 6: char_code = "S"; 7: char_code = "E"; 8: char_code = "Q"; 9: char_code = "U";
                10: char_code = "E"; 11: char_code = "N"; 12: char_code = "C"; 13: char_code = "E"; 14: char_code = "R";
                15: char_code = " "; 16: char_code = "("; 17: char_code = "4"; 18: char_code = "C"; 19: char_code = "H";
                20: char_code = "/"; 21: char_code = "6"; 22: char_code = "4"; 23: char_code = "E"; 24: char_code = "V";
                25: char_code = "T"; 26: char_code = ")";
                default: char_code = " ";
            endcase
        end
        // 4 Tracks rows at Y=344 + t*26
        else if (v_coord >= 10'd344 && v_coord < 10'd448 && h_coord >= 11'd552 && h_coord < 11'd768) begin
            track_row_id     = (v_coord - 10'd344) / 26;
            text_y           = (v_coord - 10'd344) % 26;
            curr_track_count = track_evt_count(track_row_id);
            if (text_y >= 7 && text_y < 15) begin
                in_text    = 1'b1;
                char_row   = text_y - 7;
                char_col   = (h_coord - 11'd552) & 3'b111;
                char_color = (track_row_id == selected_track) ? COLOR_PANEL : COLOR_INK;

                // "TRK 1" at X=552..591
                if (h_coord < 11'd600) begin
                    char_col = (h_coord - 11'd552) & 3'b111;
                    case ((h_coord - 11'd552) >> 3)
                        0: char_code = "T"; 1: char_code = "R"; 2: char_code = "K"; 3: char_code = " ";
                        4: char_code = 8'h31 + track_row_id;
                        default: char_code = " ";
                    endcase
                end
                // "REC" at X=610..633
                else if (h_coord >= 11'd610 && h_coord < 11'd634) begin
                    char_col = (h_coord - 11'd610) & 3'b111;
                    if (recording[track_row_id]) begin
                        char_color = (track_row_id == selected_track) ? COLOR_PANEL : COLOR_ALERT;
                        case ((h_coord - 11'd610) >> 3)
                            0: char_code = "R"; 1: char_code = "E"; 2: char_code = "C"; default: char_code = " ";
                        endcase
                    end else begin
                        char_color = (track_row_id == selected_track) ? COLOR_PANEL : COLOR_DIM;
                        case ((h_coord - 11'd610) >> 3)
                            0: char_code = "-"; 1: char_code = "-"; 2: char_code = "-"; default: char_code = " ";
                        endcase
                    end
                end
                // "PLAY" at X=650..681
                else if (h_coord >= 11'd650 && h_coord < 11'd682) begin
                    char_col = (h_coord - 11'd650) & 3'b111;
                    if (playing[track_row_id]) begin
                        char_color = (track_row_id == selected_track) ? COLOR_PANEL : COLOR_PLAY;
                        case ((h_coord - 11'd650) >> 3)
                            0: char_code = "P"; 1: char_code = "L"; 2: char_code = "A"; 3: char_code = "Y"; default: char_code = " ";
                        endcase
                    end else begin
                        char_color = (track_row_id == selected_track) ? COLOR_PANEL : COLOR_DIM;
                        case ((h_coord - 11'd650) >> 3)
                            0: char_code = "-"; 1: char_code = "-"; 2: char_code = "-"; 3: char_code = "-"; default: char_code = " ";
                        endcase
                    end
                end
                // "E:XX/40" at X=700..755
                else if (h_coord >= 11'd700 && h_coord < 11'd756) begin
                    char_col = (h_coord - 11'd700) & 3'b111;
                    case ((h_coord - 11'd700) >> 3)
                        0: char_code = "E"; 1: char_code = ":";
                        2: char_code = hex_digit((curr_track_count >> 4) & 4'hF);
                        3: char_code = hex_digit(curr_track_count & 4'hF);
                        4: char_code = "/"; 5: char_code = "4"; 6: char_code = "0";
                        default: char_code = " ";
                    endcase
                end
            end
        end

        // -------------------------------------------------------------
        // 7. Volume Level
        // -------------------------------------------------------------
        // Title at X=544, Y=473 (1X)
        else if (v_coord >= 10'd473 && v_coord < 10'd481 && h_coord >= 11'd544 && h_coord < 11'd760) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd473;
            char_col   = (h_coord - 11'd544) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd544) >> 3)
                0: char_code = "V"; 1: char_code = "O"; 2: char_code = "L"; 3: char_code = "U"; 4: char_code = "M";
                5: char_code = "E"; 6: char_code = " "; 7: char_code = "L"; 8: char_code = "E"; 9: char_code = "V";
                10: char_code = "E"; 11: char_code = "L"; 12: char_code = " "; 13: char_code = "("; 14: char_code = "0";
                15: char_code = "."; 16: char_code = "."; 17: char_code = "1"; 18: char_code = "5"; 19: char_code = ")";
                default: char_code = " ";
            endcase
        end
        // "VOL: 12 / 15" at X=552, Y=492
        else if (v_coord >= 10'd492 && v_coord < 10'd500 && h_coord >= 11'd552 && h_coord < 11'd648) begin
            in_text    = 1'b1;
            char_row   = v_coord - 10'd492;
            char_col   = (h_coord - 11'd552) & 3'b111;
            char_color = COLOR_INK;
            case ((h_coord - 11'd552) >> 3)
                0: char_code = "V"; 1: char_code = "O"; 2: char_code = "L"; 3: char_code = ":"; 4: char_code = " ";
                5: char_code = (volume >= 4'd10) ? "1" : "0";
                6: char_code = dec_digit({1'b0, volume});
                7: char_code = " "; 8: char_code = "/"; 9: char_code = " "; 10: char_code = "1"; 11: char_code = "5";
                default: char_code = " ";
            endcase
        end

        // -------------------------------------------------------------
        // 8. Footer Keybinding Hints
        // -------------------------------------------------------------
        // Footer bar text at Y=572..579
        else if (v_coord >= 10'd572 && v_coord < 10'd580 && h_coord >= 11'd20 && h_coord < 11'd780) begin
            in_text  = 1'b1;
            char_row = v_coord - 10'd572;
            char_col = (h_coord - 11'd20) & 3'b111;

            // "F9/SPACE REC" at X=20..115
            if (h_coord < 11'd120) begin
                char_color = COLOR_ALERT;
                case ((h_coord - 11'd20) >> 3)
                    0: char_code = "F"; 1: char_code = "9"; 2: char_code = "/"; 3: char_code = "S"; 4: char_code = "P";
                    5: char_code = "A"; 6: char_code = "C"; 7: char_code = "E"; 8: char_code = " "; 9: char_code = "R";
                    10: char_code = "E"; 11: char_code = "C";
                    default: char_code = " ";
                endcase
            end
            // "ENTER PLAY" at X=150..229
            else if (h_coord >= 11'd150 && h_coord < 11'd230) begin
                char_color = COLOR_PLAY;
                case ((h_coord - 11'd150) >> 3)
                    0: char_code = "E"; 1: char_code = "N"; 2: char_code = "T"; 3: char_code = "E"; 4: char_code = "R";
                    5: char_code = " "; 6: char_code = "P"; 7: char_code = "L"; 8: char_code = "A"; 9: char_code = "Y";
                    default: char_code = " ";
                endcase
            end
            // "ESC STOP" at X=260..323
            else if (h_coord >= 11'd260 && h_coord < 11'd324) begin
                char_color = COLOR_INK;
                case ((h_coord - 11'd260) >> 3)
                    0: char_code = "E"; 1: char_code = "S"; 2: char_code = "C"; 3: char_code = " ";
                    4: char_code = "S"; 5: char_code = "T"; 6: char_code = "O"; 7: char_code = "P";
                    default: char_code = " ";
                endcase
            end
            // "TAB/BS TRACK" at X=355..450
            else if (h_coord >= 11'd355 && h_coord < 11'd451) begin
                char_color = COLOR_INK;
                case ((h_coord - 11'd355) >> 3)
                    0: char_code = "T"; 1: char_code = "A"; 2: char_code = "B"; 3: char_code = "/"; 4: char_code = "B";
                    5: char_code = "S"; 6: char_code = " "; 7: char_code = "T"; 8: char_code = "R"; 9: char_code = "A";
                    10: char_code = "C"; 11: char_code = "K";
                    default: char_code = " ";
                endcase
            end
            // "ARROWS WAVE" at X=480..567
            else if (h_coord >= 11'd480 && h_coord < 11'd568) begin
                char_color = COLOR_INK;
                case ((h_coord - 11'd480) >> 3)
                    0: char_code = "A"; 1: char_code = "R"; 2: char_code = "R"; 3: char_code = "O"; 4: char_code = "W";
                    5: char_code = "S"; 6: char_code = " "; 7: char_code = "W"; 8: char_code = "A"; 9: char_code = "V";
                    10: char_code = "E";
                    default: char_code = " ";
                endcase
            end
            // "NEXYS A7 FPGA" at X=670..773
            else if (h_coord >= 11'd670 && h_coord < 11'd774) begin
                char_color = COLOR_ACCENT;
                case ((h_coord - 11'd670) >> 3)
                    0: char_code = "N"; 1: char_code = "E"; 2: char_code = "X"; 3: char_code = "Y"; 4: char_code = "S";
                    5: char_code = " "; 6: char_code = "A"; 7: char_code = "7"; 8: char_code = " "; 9: char_code = "F";
                    10: char_code = "P"; 11: char_code = "G"; 12: char_code = "A";
                    default: char_code = " ";
                endcase
            end
        end
    end

    // Visual geometry and raster pixel compositing
    reg [11:0] pixel_color;

    // Intermediate geometry flags
    reg is_screen_border;
    reg is_card_panel;
    reg is_card_border;
    reg is_piano_grid_h;
    reg is_piano_grid_v;
    reg is_piano_c_root;
    reg is_piano_key_tag;
    reg is_piano_active_key;
    reg is_piano_active_row;
    reg is_piano_note_cell;
    reg is_playhead_line;
    reg is_rec_indicator;
    reg is_status_badge;
    reg is_wave_btn;
    reg is_scope_screen;
    reg is_scope_grid;
    reg is_scope_trace;
    reg is_track_row_active;
    reg is_track_row_box;
    reg is_vol_seg_active;
    reg is_vol_seg_border;

    integer r_idx, s_idx, v_idx;
    reg [4:0] roll_pitch;
    reg [3:0] roll_step;

    always_comb begin
        // 1. Outer screen 2px border
        is_screen_border = (h_coord <= 11'd1 || h_coord >= 11'd798 || v_coord <= 10'd1 || v_coord >= 10'd598);

        // 2. Card Panel backgrounds & borders
        is_card_panel = 1'b0;
        is_card_border = 1'b0;

        // Header card (Y: 2..39)
        if (v_coord >= 10'd2 && v_coord < 10'd40 && h_coord >= 11'd2 && h_coord < 11'd798) begin
            is_card_panel = 1'b1;
            if (v_coord == 10'd39) is_card_border = 1'b1;
        end
        // Piano Roll card (X: 14..524, Y: 46..544)
        else if (v_coord >= 10'd46 && v_coord < 10'd545 && h_coord >= 11'd14 && h_coord < 11'd525) begin
            is_card_panel = 1'b1;
            if (h_coord == 11'd14 || h_coord == 11'd524 || v_coord == 10'd46 || v_coord == 10'd544 || v_coord == 10'd64)
                is_card_border = 1'b1;
        end
        // Wave Select card (X: 536..786, Y: 46..88)
        else if (v_coord >= 10'd46 && v_coord < 10'd89 && h_coord >= 11'd536 && h_coord < 11'd787) begin
            is_card_panel = 1'b1;
            if (h_coord == 11'd536 || h_coord == 11'd786 || v_coord == 10'd46 || v_coord == 10'd88 || v_coord == 10'd64)
                is_card_border = 1'b1;
        end
        // Oscilloscope card (X: 536..786, Y: 94..312)
        else if (v_coord >= 10'd94 && v_coord < 10'd313 && h_coord >= 11'd536 && h_coord < 11'd787) begin
            is_card_panel = 1'b1;
            if (h_coord == 11'd536 || h_coord == 11'd786 || v_coord == 10'd94 || v_coord == 10'd312 || v_coord == 10'd112)
                is_card_border = 1'b1;
        end
        // Track Sequencer card (X: 536..786, Y: 318..460)
        else if (v_coord >= 10'd318 && v_coord < 10'd461 && h_coord >= 11'd536 && h_coord < 11'd787) begin
            is_card_panel = 1'b1;
            if (h_coord == 11'd536 || h_coord == 11'd786 || v_coord == 10'd318 || v_coord == 10'd460 || v_coord == 10'd336)
                is_card_border = 1'b1;
        end
        // Volume Level card (X: 536..786, Y: 468..544)
        else if (v_coord >= 10'd468 && v_coord < 10'd545 && h_coord >= 11'd536 && h_coord < 11'd787) begin
            is_card_panel = 1'b1;
            if (h_coord == 11'd536 || h_coord == 11'd786 || v_coord == 10'd468 || v_coord == 10'd544 || v_coord == 10'd486)
                is_card_border = 1'b1;
        end
        // Footer card (Y: 556..597)
        else if (v_coord >= 10'd556 && v_coord < 10'd598 && h_coord >= 11'd2 && h_coord < 11'd798) begin
            is_card_panel = 1'b1;
            if (v_coord == 10'd556) is_card_border = 1'b1;
        end

        // 3. Piano Roll Grid & Notes (Y: 92..539, X: 68..515)
        is_piano_grid_h     = 1'b0;
        is_piano_grid_v     = 1'b0;
        is_piano_c_root     = 1'b0;
        is_piano_key_tag    = 1'b0;
        is_piano_active_key = 1'b0;
        is_piano_active_row = 1'b0;
        is_piano_note_cell  = 1'b0;

        if (v_coord >= 10'd92 && v_coord < 10'd540) begin
            r_idx = (v_coord - 10'd92) >> 4;
            roll_pitch = 5'd27 - r_idx;

            // Horizontal grid lines: only inside key tags and step columns
            if ((v_coord - 10'd92) % 16 == 15) begin
                if ((h_coord >= 11'd16 && h_coord <= 11'd65) || (h_coord >= 11'd68 && h_coord <= 11'd515))
                    is_piano_grid_h = 1'b1;
            end

            // Key tag on left (X: 16..65)
            if (h_coord >= 11'd16 && h_coord <= 11'd65) begin
                if (h_coord == 11'd16 || h_coord == 11'd65 || ((v_coord - 10'd92) % 16 == 0))
                    is_card_border = 1'b1;
                else begin
                    is_piano_key_tag = 1'b1;
                    if (active_note_valid && (roll_pitch == current_active_pitch))
                        is_piano_active_key = 1'b1;
                end
            end

            // Vertical grid lines, C-root row tint, and note blocks across 16 columns (X: 68..515)
            if (h_coord >= 11'd68 && h_coord < 11'd516) begin
                // C root row check (C1=0, C2=7, C3=14, C4=21) - inside grid area only
                if (roll_pitch % 7 == 0)
                    is_piano_c_root = 1'b1;

                if (active_note_valid && (roll_pitch == current_active_pitch))
                    is_piano_active_row = 1'b1;

                s_idx = (h_coord - 11'd68) / 28;
                // Vertical divider line
                if ((h_coord - 11'd68) % 28 == 0 || (h_coord == 11'd515))
                    is_piano_grid_v = 1'b1;

                // Check active cell in roll_matrix
                if (s_idx < 16 && roll_pitch < 28) begin
                    if (roll_matrix[roll_pitch * 16 + s_idx]) begin
                        // 2px margin inside cell
                        if (((h_coord - 11'd68) % 28 >= 2) && ((h_coord - 11'd68) % 28 < 26) &&
                            ((v_coord - 10'd92) % 16 >= 2) && ((v_coord - 10'd92) % 16 < 14)) begin
                            is_piano_note_cell = 1'b1;
                        end
                    end
                end
            end
        end

        // 4. Red Playhead Running Line (width 2px)
        is_playhead_line = 1'b0;
        if (playhead_active && (v_coord >= 10'd70 && v_coord < 10'd540)) begin
            if (h_coord >= playhead_x && h_coord <= playhead_x + 11'd1)
                is_playhead_line = 1'b1;
        end

        // 5. Header Indicators (REC dot & Status badge)
        is_rec_indicator = 1'b0;
        if (|recording && rec_blink) begin
            if (h_coord >= 11'd580 && h_coord <= 11'd588 && v_coord >= 10'd17 && v_coord <= 10'd25)
                is_rec_indicator = 1'b1;
        end

        is_status_badge = (h_coord >= 11'd640 && h_coord < 11'd704 && v_coord >= 10'd10 && v_coord < 10'd32);

        // 6. Waveform Selector Buttons (X: 542 + w*59, width 54, Y: 68..83)
        is_wave_btn = 1'b0;
        if (v_coord >= 10'd68 && v_coord < 10'd84 && h_coord >= 11'd542 && h_coord < 11'd778) begin
            if ((h_coord - 11'd542) % 59 < 54) begin
                if (((h_coord - 11'd542) / 59) == waveform_select)
                    is_wave_btn = 1'b1;
            end
        end

        // 7. Oscilloscope Screen (X: 544..778, Y: 116..304)
        is_scope_screen = 1'b0;
        is_scope_grid   = 1'b0;
        is_scope_trace  = 1'b0;
        if (h_coord >= 11'd544 && h_coord < 11'd778 && v_coord >= 10'd116 && v_coord < 10'd304) begin
            is_scope_screen = 1'b1;
            // Center horizontal zero line
            if (v_coord == 10'd210)
                is_scope_grid = 1'b1;
            // Reticle grid every 47px vertically and 46px horizontally (dotted)
            else if ((v_coord == 10'd163 || v_coord == 10'd257) && ((h_coord & 11'd4) == 0))
                is_scope_grid = 1'b1;
            else if ((h_coord == 11'd590 || h_coord == 11'd636 || h_coord == 11'd682 || h_coord == 11'd728) && ((v_coord & 10'd4) == 0))
                is_scope_grid = 1'b1;

            // Oscilloscope trace curve (thickness 3px)
            if (v_coord >= wave_curve_y - 1 && v_coord <= wave_curve_y + 1)
                is_scope_trace = 1'b1;
        end

        // 8. 4-Track Sequencer Rows (Y: 344 + t*26, height 22, X: 544..778)
        is_track_row_active = 1'b0;
        is_track_row_box    = 1'b0;
        if (v_coord >= 10'd344 && v_coord < 10'd448 && h_coord >= 11'd544 && h_coord < 11'd778) begin
            if ((v_coord - 10'd344) % 26 < 22) begin
                is_track_row_box = 1'b1;
                if (((v_coord - 10'd344) / 26) == selected_track)
                    is_track_row_active = 1'b1;
            end
        end

        // 9. Volume Bar 16 Segments (X: 552 + v*14, width 12, Y: 508..524)
        is_vol_seg_active = 1'b0;
        is_vol_seg_border = 1'b0;
        if (v_coord >= 10'd508 && v_coord < 10'd524 && h_coord >= 11'd552 && h_coord < 11'd776) begin
            v_idx = (h_coord - 11'd552) / 14;
            if ((h_coord - 11'd552) % 14 < 12) begin
                if (h_coord == 11'd552 + v_idx * 14 || h_coord == 11'd552 + v_idx * 14 + 11 ||
                    v_coord == 10'd508 || v_coord == 10'd523)
                    is_vol_seg_border = 1'b1;
                else if (v_idx < volume)
                    is_vol_seg_active = 1'b1;
            end
        end

        // -------------------------------------------------------------
        // Priority Color Multiplexing
        // -------------------------------------------------------------
        pixel_color = COLOR_BG;

        if (is_card_panel)
            pixel_color = COLOR_PANEL;

        if (is_piano_c_root)
            pixel_color = COLOR_C_ROOT;

        if (is_piano_active_row)
            pixel_color = 12'hFFB; // Soft amber tint for the active note row

        if (is_piano_key_tag)
            pixel_color = (roll_pitch % 7 == 0) ? COLOR_ACCENT : COLOR_PANEL;

        if (is_piano_active_key)
            pixel_color = COLOR_ALERT; // Bright highlighted active piano key

        if (is_piano_grid_h)
            pixel_color = is_piano_c_root ? COLOR_ACCENT : COLOR_GRID;

        if (is_piano_grid_v)
            pixel_color = (s_idx % 4 == 0) ? COLOR_INK : COLOR_GRID;

        if (is_piano_note_cell)
            pixel_color = COLOR_ACCENT;

        if (is_scope_screen)
            pixel_color = COLOR_SCOPE_BG;

        if (is_scope_grid)
            pixel_color = COLOR_SCOPE_GRID;

        if (is_scope_trace)
            pixel_color = COLOR_SCOPE_TRACE;

        if (is_track_row_box)
            pixel_color = is_track_row_active ? COLOR_ACCENT : COLOR_BG;

        if (is_wave_btn)
            pixel_color = COLOR_ACCENT;

        if (is_vol_seg_active)
            pixel_color = (v_idx >= 13) ? COLOR_ALERT : COLOR_ACCENT;

        if (is_status_badge)
            pixel_color = (|playing) ? COLOR_PLAY : (audio_play ? COLOR_ACCENT : 12'hDDD);

        if (is_rec_indicator)
            pixel_color = COLOR_ALERT;

        if (is_playhead_line)
            pixel_color = COLOR_ALERT;

        if (is_card_border || is_vol_seg_border)
            pixel_color = COLOR_INK;

        if (text_pixel)
            pixel_color = char_color;

        if (is_screen_border)
            pixel_color = COLOR_INK;

        if (!rst_n)
            pixel_color = 12'h000;

        {red, green, blue} = pixel_color;
    end

endmodule
