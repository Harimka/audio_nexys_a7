// 800x600 workstation UI. All inputs are a pixel-domain snapshot
// prepared by audio_nexys_a7; this module contains combinational pixel logic.
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
    localparam [11:0] COLOR_BG     = 12'hFEA;
    localparam [11:0] COLOR_INK    = 12'h111;
    localparam [11:0] COLOR_ACCENT = 12'h06F;
    localparam [11:0] COLOR_ALERT  = 12'hF33;

    reg [4:0] small_field;
    reg [5:0] small_char_index;
    reg [2:0] small_row;
    reg [2:0] small_column;
    reg [7:0] small_char_code;
    wire [7:0] small_glyph_bits;
    wire small_text_pixel;
    reg [7:0] large_char_code;
    reg [2:0] large_row;
    wire [7:0] large_glyph_bits;
    wire large_text_pixel;
    reg [3:0] track_index;
    reg [3:0] event_digit;
    reg [3:0] preview_digit;
    reg [4:0] selected_preview_count;
    reg [6:0] selected_event_count;
    reg selected_recording;
    reg any_playing;
    reg [4:0] preview_note;
    reg [5:0] grid_row;
    reg [4:0] grid_step;
    reg [5:0] note_pitch_row;
    reg [7:0] key_char_code;
    reg [7:0] key_octave_code;
    reg [2:0] key_glyph_row;
    wire [7:0] key_glyph_bits;
    wire [7:0] key_octave_glyph_bits;
    wire font_rom_footer_pixel;
    reg [7:0] footer_char_code;
    reg [2:0] footer_row;
    wire [7:0] footer_glyph_bits;
    reg [10:0] wave_x_offset;
    wire [7:0] wave_phase_addr;
    wire [31:0] wave_phase;
    wire [15:0] wave_preview_sample;
    wire signed [16:0] wave_centered;
    integer wave_curve_y;
    reg [11:0] pixel_color;
    reg is_frame;
    reg is_grid;
    reg is_key_border;
    reg is_note_block;
    reg is_wave_line;
    reg is_header;
    reg is_footer;
    reg is_rec_dot;
    reg [23:0] rec_blink_counter;
    reg rec_blink;
    reg is_track_selected;
    reg [9:0] row_y;
    reg [10:0] slot_x;

    function automatic [6:0] count_at(input [1:0] index);
        begin
            case (index)
                2'd0: count_at = event_counts[6:0];
                2'd1: count_at = event_counts[13:7];
                2'd2: count_at = event_counts[20:14];
                default: count_at = event_counts[27:21];
            endcase
        end
    endfunction

    function automatic [4:0] preview_count_at(input [1:0] index);
        begin
            case (index)
                2'd0: preview_count_at = preview_counts[4:0];
                2'd1: preview_count_at = preview_counts[9:5];
                2'd2: preview_count_at = preview_counts[14:10];
                default: preview_count_at = preview_counts[19:15];
            endcase
        end
    endfunction

    function automatic [4:0] note_at(input [1:0] track, input [3:0] step);
        reg [8:0] bit_address;
        begin
            bit_address = track * 9'd80 + step * 9'd5;
            note_at = preview_notes[bit_address +: 5];
        end
    endfunction

    function automatic [7:0] hex_ascii(input [3:0] value);
        begin
            hex_ascii = (value < 10) ? (8'h30 + value) : (8'h41 + value - 10);
        end
    endfunction

    function automatic [7:0] decimal_ascii(input [4:0] value);
        begin
            decimal_ascii = (value < 10) ? (8'h30 + value) : (8'h30 + value - 10);
        end
    endfunction

    function automatic [7:0] note_ascii(input [2:0] note);
        begin
            case (note)
                3'd0: note_ascii = "C";
                3'd1: note_ascii = "D";
                3'd2: note_ascii = "E";
                3'd3: note_ascii = "F";
                3'd4: note_ascii = "G";
                3'd5: note_ascii = "A";
                default: note_ascii = "B";
            endcase
        end
    endfunction

    function automatic [7:0] wave_ascii(input [1:0] wave, input [3:0] index);
        begin
            wave_ascii = 8'h20;
            case (wave)
                2'd0: case (index) 0: wave_ascii="S"; 1: wave_ascii="I"; 2: wave_ascii="N"; 3: wave_ascii="E"; default: ; endcase
                2'd1: case (index) 0: wave_ascii="T"; 1: wave_ascii="R"; 2: wave_ascii="I"; 3: wave_ascii="A"; 4: wave_ascii="N"; 5: wave_ascii="G"; 6: wave_ascii="L"; 7: wave_ascii="E"; default: ; endcase
                2'd2: case (index) 0: wave_ascii="S"; 1: wave_ascii="Q"; 2: wave_ascii="U"; 3: wave_ascii="A"; 4: wave_ascii="R"; 5: wave_ascii="E"; default: ; endcase
                default: case (index) 0: wave_ascii="S"; 1: wave_ascii="A"; 2: wave_ascii="W"; default: ; endcase
            endcase
        end
    endfunction

    function automatic [7:0] standard_text(input [4:0] field, input [5:0] index);
        reg [1:0] row_track;
        reg [6:0] row_count;
        begin
            standard_text = 8'h20;
            case (field)
                5'd0: case (index)
                    0: standard_text = "N"; 1: standard_text = "E"; 2: standard_text = "X"; 3: standard_text = "Y"; 4: standard_text = "S"; 5: standard_text = " "; 6: standard_text = "A"; 7: standard_text = "7";
                    8: standard_text = " "; 9: standard_text = "/"; 10: standard_text = " "; 11: standard_text = "S"; 12: standard_text = "Y"; 13: standard_text = "N"; 14: standard_text = "T"; 15: standard_text = "H"; default:;
                endcase
                5'd1: case (index) 0: standard_text = "R"; 1: standard_text = "E"; 2: standard_text = "C"; default:; endcase
                5'd2: if (|playing) begin
                    case (index) 0: standard_text = "P"; 1: standard_text = "L"; 2: standard_text = "A"; 3: standard_text = "Y"; default:; endcase
                end else if (audio_play) begin
                    case (index) 0: standard_text = "L"; 1: standard_text = "I"; 2: standard_text = "V"; 3: standard_text = "E"; default:; endcase
                end else begin
                    case (index) 0: standard_text = "I"; 1: standard_text = "D"; 2: standard_text = "L"; 3: standard_text = "E"; default:; endcase
                end
                5'd3: case (index)
                    0: standard_text = "P"; 1: standard_text = "I"; 2: standard_text = "A"; 3: standard_text = "N"; 4: standard_text = "O"; 5: standard_text = " "; 6: standard_text = "R"; 7: standard_text = "O"; 8: standard_text = "L"; 9: standard_text = "L"; default:;
                endcase
                5'd4: case (index)
                    0: standard_text = "T"; 1: standard_text = "R"; 2: standard_text = "A"; 3: standard_text = "C"; 4: standard_text = "K"; 5: standard_text = " "; 6: standard_text = hex_ascii({2'b00,selected_track}+4'd1);
                    7: standard_text = " "; 8: standard_text = "N"; 9: standard_text = "O"; 10: standard_text = "T"; 11: standard_text = "E"; 12: standard_text = "S";
                    13: standard_text = " "; 14: standard_text = hex_ascii({1'b0, selected_event_count[6:4]});
                    15: standard_text = hex_ascii(selected_event_count[3:0]); 16: standard_text = "/"; 17: standard_text = "6"; 18: standard_text = "4"; default:;
                endcase
                5'd5: case (index)
                    0: standard_text = "W"; 1: standard_text = "A"; 2: standard_text = "V"; 3: standard_text = "E"; 4: standard_text = "F"; 5: standard_text = "O"; 6: standard_text = "R"; 7: standard_text = "M"; default:;
                endcase
                5'd6: standard_text = wave_ascii(waveform_select, index[3:0]);
                5'd7: case (index)
                    0: standard_text = "A"; 1: standard_text = "C"; 2: standard_text = "T"; 3: standard_text = "I"; 4: standard_text = "V"; 5: standard_text = "E"; 6: standard_text = " "; 7: standard_text = "N"; 8: standard_text = "O"; 9: standard_text = "T"; 10: standard_text = "E"; default:;
                endcase
                5'd8: case (index)
                    0: standard_text = "O"; 1: standard_text = "C"; 2: standard_text = "T"; 3: standard_text = ":"; 4: standard_text = " ";
                    5: standard_text = active_note_valid ? (8'h31 + active_octave) : 8'h2D;
                    default:;
                endcase
                5'd9: case (index) 0: standard_text = "T"; 1: standard_text = "R"; 2: standard_text = "A"; 3: standard_text = "C"; 4: standard_text = "K"; 5: standard_text = "S"; default:; endcase
                5'd10, 5'd11, 5'd12, 5'd13: begin
                    row_track = field - 5'd10;
                    row_count = count_at(row_track);
                    case (index)
                        0: standard_text = "T"; 1: standard_text = hex_ascii({2'b00,row_track}+4'd1); 2: standard_text = " "; 3: standard_text = "E";
                        4: standard_text = hex_ascii(row_count[6:4]); 5: standard_text = hex_ascii(row_count[3:0]); 6: standard_text = " ";
                        7: standard_text = recording[row_track] ? "R" : "-";
                        8: standard_text = " "; 9: standard_text = playing[row_track] ? "P" : "-";
                        default:;
                    endcase
                end
                5'd14: case (index) 0: standard_text = "V"; 1: standard_text = "O"; 2: standard_text = "L"; default:; endcase
                5'd15: begin
                    if (index < 32) begin
                        if (index[0]) standard_text = decimal_ascii((index >> 1) + 1);
                        else standard_text = (((index >> 1) + 1) >= 10) ? "1" : "0";
                    end
                end
                5'd16: begin
                    case (index)
                        0:standard_text="S"; 1:standard_text="I"; 2:standard_text="N";
                        3:standard_text="T"; 4:standard_text="R"; 5:standard_text="I";
                        6:standard_text="S"; 7:standard_text="Q"; 8:standard_text="R";
                        9:standard_text="S"; 10:standard_text="A"; 11:standard_text="W";
                        default:standard_text=8'h20;
                    endcase
                end
                5'd17: begin
                    case (index)
                        0:standard_text="L"; 1:standard_text="I"; 2:standard_text="V"; 3:standard_text="E";
                        default:standard_text=8'h20;
                    endcase
                end
                default: standard_text = 8'h20;
            endcase
        end
    endfunction

    font_rom small_font (
        .char_code(small_char_code), .row(small_row), .bits(small_glyph_bits)
    );
    font_rom large_font (
        .char_code(large_char_code), .row(large_row), .bits(large_glyph_bits)
    );
    font_rom key_font (
        .char_code(key_char_code), .row(key_glyph_row), .bits(key_glyph_bits)
    );
    font_rom key_octave_font (
        .char_code(key_octave_code), .row(key_glyph_row), .bits(key_octave_glyph_bits)
    );

    assign small_text_pixel = (small_field == 5'd15 && ((h_coord-11'd60) % 15) >= 8)
                            ? 1'b0 : small_glyph_bits[7-small_column];
    assign large_text_pixel = large_glyph_bits[7-((h_coord-11'd600) >> 2) % 8];
    assign wave_phase_addr = wave_x_offset[7:0] + (wave_x_offset[7:3]);
    assign wave_phase = {wave_phase_addr, 24'b0};
    assign wave_centered = $signed({1'b0,wave_preview_sample}) - 17'sd32768;
    waveform_lookup waveform_preview (
        .phase(wave_phase), .waveform_select(waveform_select), .sample(wave_preview_sample)
    );

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            rec_blink_counter <= 24'd0;
            rec_blink <= 1'b0;
        end else if (rec_blink_counter == 24'd9_999_999) begin
            rec_blink_counter <= 24'd0;
            rec_blink <= ~rec_blink;
        end else begin
            rec_blink_counter <= rec_blink_counter + 1'b1;
        end
    end

    always @* begin
        selected_event_count = count_at(selected_track);
        selected_preview_count = preview_count_at(selected_track);
        selected_recording = recording[selected_track];
        any_playing = |playing;
        wave_x_offset = (h_coord >= 11'd562) ? h_coord - 11'd562 : 11'd0;
        wave_curve_y = 174 - ($signed(wave_centered) >>> 9);

        small_field = 5'd31;
        small_char_index = 0;
        small_row = 0;
        small_column = 0;
        small_char_code = 8'h20;
        if (v_coord >= 10'd12 && v_coord < 10'd28 && h_coord >= 11'd16 && h_coord < 11'd272) begin
            small_field = 5'd0; small_char_index = (h_coord-11'd16) >> 4;
            small_row = (v_coord-10'd12) >> 1; small_column = ((h_coord-11'd16) >> 1) & 3'b111;
        end else if (v_coord >= 10'd12 && v_coord < 10'd28 && h_coord >= 11'd642 && h_coord < 11'd690) begin
            small_field = 5'd1; small_char_index = (h_coord-11'd642) >> 4;
            small_row = (v_coord-10'd12) >> 1; small_column = ((h_coord-11'd642) >> 1) & 3'b111;
        end else if (v_coord >= 10'd12 && v_coord < 10'd28 && h_coord >= 11'd710 && h_coord < 11'd774) begin
            small_field = 5'd2; small_char_index = (h_coord-11'd710) >> 4;
            small_row = (v_coord-10'd12) >> 1; small_column = ((h_coord-11'd710) >> 1) & 3'b111;
        end else if (v_coord >= 10'd49 && v_coord < 10'd65 && h_coord >= 11'd12 && h_coord < 11'd172) begin
            small_field = 5'd3; small_char_index = (h_coord-11'd12) >> 4;
            small_row = (v_coord-10'd49) >> 1; small_column = ((h_coord-11'd12) >> 1) & 3'b111;
        end else if (v_coord >= 10'd49 && v_coord < 10'd65 && h_coord >= 11'd168 && h_coord < 11'd472) begin
            small_field = 5'd4; small_char_index = (h_coord-11'd168) >> 4;
            small_row = (v_coord-10'd49) >> 1; small_column = ((h_coord-11'd168) >> 1) & 3'b111;
        end else if (v_coord >= 10'd49 && v_coord < 10'd65 && h_coord >= 11'd562 && h_coord < 11'd690) begin
            small_field = 5'd5; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd49) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd84 && v_coord < 10'd100 && h_coord >= 11'd566 && h_coord < 11'd694) begin
            small_field = 5'd6; small_char_index = (h_coord-11'd566) >> 4;
            small_row = (v_coord-10'd84) >> 1; small_column = ((h_coord-11'd566) >> 1) & 3'b111;
        end else if (v_coord >= 10'd306 && v_coord < 10'd322 && h_coord >= 11'd562 && h_coord < 11'd738) begin
            small_field = 5'd7; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd306) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd405 && v_coord < 10'd421 && h_coord >= 11'd562 && h_coord < 11'd658) begin
            small_field = 5'd8; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd405) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd440 && v_coord < 10'd456 && h_coord >= 11'd562 && h_coord < 11'd658) begin
            small_field = 5'd9; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd440) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd460 && v_coord < 10'd476 && h_coord >= 11'd562 && h_coord < 11'd722) begin
            small_field = 5'd10; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd460) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd480 && v_coord < 10'd496 && h_coord >= 11'd562 && h_coord < 11'd722) begin
            small_field = 5'd11; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd480) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd500 && v_coord < 10'd516 && h_coord >= 11'd562 && h_coord < 11'd722) begin
            small_field = 5'd12; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd500) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd520 && v_coord < 10'd536 && h_coord >= 11'd562 && h_coord < 11'd722) begin
            small_field = 5'd13; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd520) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end else if (v_coord >= 10'd538 && v_coord < 10'd554 && h_coord >= 11'd562 && h_coord < 11'd610) begin
            small_field = 5'd14; small_char_index = (h_coord-11'd562) >> 4;
            small_row = (v_coord-10'd538) >> 1; small_column = ((h_coord-11'd562) >> 1) & 3'b111;
        end
        if (v_coord >= 10'd70 && v_coord < 10'd78 && h_coord >= 11'd60 && h_coord < 11'd540) begin
            small_field = 5'd15;
            small_char_index = (h_coord-11'd60) / 15;
            small_row = v_coord - 10'd70;
            small_column = (h_coord-11'd60) % 15;
        end
        if (v_coord >= 10'd64 && v_coord < 10'd80 && h_coord >= 11'd562 && h_coord < 11'd786) begin
            small_field = 5'd16;
            small_char_index = ((h_coord-11'd562) / 56) * 3 + (((h_coord-11'd562) % 56) >> 4);
            small_row = (v_coord-10'd64) >> 1;
            small_column = (((h_coord-11'd562) % 56) >> 1) & 3'b111;
        end
        if (small_field != 5'd31)
            small_char_code = standard_text(small_field, small_char_index);

        // Large active-note display: C1..B4, or two dashes when idle.
        large_row = 3'd0;
        if (h_coord >= 11'd600 && h_coord < 11'd664 && v_coord >= 10'd340 && v_coord < 10'd372) begin
            large_row = (v_coord-10'd340) >> 2;
            if (!active_note_valid)
                large_char_code = ((h_coord-11'd600) < 11'd32) ? "-" : "-";
            else if ((h_coord-11'd600) < 11'd32)
                large_char_code = note_ascii(active_note);
            else
                large_char_code = 8'h31 + active_octave;
        end else begin
            large_char_code = 8'h20;
        end

        grid_row = 0;
        grid_step = 0;
        row_y = 0;
        slot_x = 0;
        preview_note = 0;
        note_pitch_row = 0;
        if (v_coord >= 10'd92 && v_coord < 10'd540) begin
            grid_row = (v_coord-10'd92) >> 4;
            row_y = 10'd92 + grid_row * 16;
            note_pitch_row = 6'd27 - grid_row;
        end
        if (h_coord >= 11'd60 && h_coord < 11'd540) begin
            grid_step = (h_coord-11'd60) / 30;
            slot_x = 11'd60 + grid_step * 30;
            preview_note = note_at(selected_track, grid_step[3:0]);
        end
        is_note_block = 1'b0;
        if (v_coord >= 10'd92 && v_coord < 10'd540 && h_coord >= 11'd60 && h_coord < 11'd540 && grid_step < 16) begin
            // Adjacent cells merge visually into a duration block; blank cells
            // remain rests, and simultaneous notes occupy separate pitch rows.
            if (roll_matrix[note_pitch_row * 16 + grid_step] &&
                h_coord >= slot_x + 11'd2 && h_coord < slot_x + 11'd28 &&
                v_coord >= row_y + 10'd2 && v_coord < row_y + 10'd14)
                is_note_block = 1'b1;
        end

        is_header = (v_coord < 10'd40);
        is_footer = (v_coord >= 10'd561);
        is_frame = (h_coord == 0 || h_coord == 11'd799 || v_coord == 0 || v_coord == 10'd599 ||
                    v_coord == 10'd39 || v_coord == 10'd40 || v_coord == 10'd560 || v_coord == 10'd561 ||
                    h_coord == 11'd540 || h_coord == 11'd541 || h_coord == 11'd550 || h_coord == 11'd799 ||
                    (v_coord >= 10'd40 && v_coord <= 10'd560 && (h_coord == 11'd0 || h_coord == 11'd799)) ||
                    (h_coord >= 11'd550 && h_coord <= 11'd798 && (v_coord == 10'd280 || v_coord == 10'd281)) ||
                    (h_coord >= 11'd550 && h_coord <= 11'd798 && (v_coord == 10'd42 || v_coord == 10'd559)));
        is_grid = ((v_coord >= 10'd92 && v_coord < 10'd540 && ((v_coord-10'd92) % 16 == 0)) ||
                   (h_coord >= 11'd60 && h_coord < 11'd540 && ((h_coord-11'd60) % 30 == 0)) ||
                   (v_coord >= 10'd66 && v_coord < 10'd92 && h_coord >= 11'd60 && h_coord < 11'd540 && ((h_coord-11'd60) % 120 == 0)));
        is_key_border = (h_coord >= 11'd0 && h_coord < 11'd60 && v_coord >= 10'd92 && v_coord < 10'd540 &&
                         ((v_coord-10'd92) % 16 == 0 || h_coord == 0 || h_coord == 11'd59));
        track_index = (v_coord >= 10'd460 && v_coord < 10'd540) ? ((v_coord-10'd460) / 20) : 4'd0;
        is_track_selected = (selected_track == track_index[1:0]);
        is_rec_dot = selected_recording && rec_blink;

        key_char_code = 8'h20;
        key_octave_code = 8'h20;
        key_glyph_row = 0;
        if (v_coord >= 10'd92 && v_coord < 10'd540 && h_coord >= 11'd8 && h_coord < 11'd52) begin
            key_glyph_row = ((v_coord-10'd92) % 16) >> 1;
            case ((27 - ((v_coord-10'd92) >> 4)) % 7)
                0:key_char_code="C"; 1:key_char_code="D"; 2:key_char_code="E";
                3:key_char_code="F"; 4:key_char_code="G"; 5:key_char_code="A"; default:key_char_code="B";
            endcase
            key_octave_code = 8'h31 + 3 - (((v_coord-10'd92) >> 4) / 7);
        end

        pixel_color = COLOR_BG;
        if (is_header)
            pixel_color = 12'hFFF;
        if (v_coord >= 10'd40 && v_coord < 10'd561 && h_coord >= 11'd0 && h_coord < 11'd540)
            pixel_color = ((note_pitch_row % 7 == 0) && v_coord >= 10'd92) ? 12'hEFF : 12'hFFF;
        if (v_coord >= 10'd40 && v_coord < 10'd561 && h_coord >= 11'd550 && h_coord < 11'd799)
            pixel_color = COLOR_BG;
        if (is_track_selected && v_coord >= 10'd460 + selected_track * 20 && v_coord < 10'd476 + selected_track * 20 &&
            h_coord >= 11'd558 && h_coord < 11'd724)
            pixel_color = COLOR_ACCENT;
        if (is_note_block)
            pixel_color = COLOR_ACCENT;
        if (v_coord >= 10'd66 && v_coord < 10'd92 && h_coord >= 11'd0 && h_coord < 11'd540)
            pixel_color = 12'hF1F;
        if (v_coord >= 10'd66 && v_coord < 10'd92 && h_coord >= 11'd60 && h_coord < 11'd540 &&
            (((h_coord-11'd60) % 120) == 0))
            pixel_color = 12'hCBD;
        if (is_rec_dot && h_coord >= 11'd630 && h_coord < 11'd642 && v_coord >= 10'd14 && v_coord < 10'd26)
            pixel_color = COLOR_ALERT;
        if (is_frame || is_grid || is_key_border)
            pixel_color = COLOR_INK;
        if (h_coord >= 11'd562 && h_coord < 11'd786 && v_coord >= 10'd64 && v_coord < 10'd80) begin
            if (((h_coord-11'd562) / 56) == waveform_select)
                pixel_color = COLOR_ACCENT;
            else
                pixel_color = 12'hDDD;
        end

        // Four-step VU bar reflects the actual 0..15 digital volume register.
        if (h_coord >= 11'd612 && h_coord < 11'd792 && v_coord >= 10'd540 && v_coord < 10'd556) begin
            if (v_coord == 10'd540 || v_coord == 10'd555 || h_coord == 11'd612 || h_coord == 11'd791)
                pixel_color = COLOR_INK;
            else if ((h_coord-11'd614) < volume * 12)
                pixel_color = COLOR_ACCENT;
        end

        // Preview one complete cycle using the selected FPGA waveform table.
        if (h_coord >= 11'd562 && h_coord < 11'd788 && v_coord >= 10'd104 && v_coord < 10'd258 &&
            ((v_coord >= wave_curve_y-1) && (v_coord <= wave_curve_y+1)))
            pixel_color = COLOR_ACCENT;
        if (h_coord >= 11'd562 && h_coord < 11'd788 && v_coord == 10'd174)
            pixel_color = COLOR_INK;
        if ((small_field != 5'd31 && small_text_pixel) || large_text_pixel)
            pixel_color = COLOR_INK;
        if (small_field == 5'd6 && small_text_pixel)
            pixel_color = COLOR_BG;
        if (small_field == 5'd16 && small_text_pixel)
            pixel_color = (((h_coord-11'd562) / 56) == waveform_select) ? 12'hFFF : COLOR_INK;
        if (small_field == 5'd1 && small_text_pixel)
            pixel_color = COLOR_ALERT;
        if (small_field >= 5'd10 && small_field <= 5'd13 && is_track_selected && small_text_pixel)
            pixel_color = COLOR_BG;
        if (small_field == 5'd2 && small_text_pixel && |playing)
            pixel_color = COLOR_ALERT;
        if (small_field == 5'd14 && small_text_pixel)
            pixel_color = COLOR_INK;
        if (((h_coord >= 11'd8 && h_coord < 11'd16) && key_glyph_bits[7-(h_coord-11'd8)]) ||
            ((h_coord >= 11'd32 && h_coord < 11'd40) && key_octave_glyph_bits[7-(h_coord-11'd32)]))
            pixel_color = COLOR_INK;
        if (is_footer && h_coord >= 11'd16 && h_coord < 11'd784 && v_coord >= 10'd575 && v_coord < 10'd583) begin
            if (font_rom_footer_pixel)
                pixel_color = COLOR_INK;
        end

        if (!rst_n)
            pixel_color = 12'h000;
        {red,green,blue} = pixel_color;
    end

    font_rom footer_font (.char_code(footer_char_code), .row(footer_row), .bits(footer_glyph_bits));
    assign font_rom_footer_pixel = footer_glyph_bits[7-((h_coord-11'd16) & 3'b111)];

    always @* begin
        if (v_coord >= 10'd575 && v_coord < 10'd583 && h_coord >= 11'd16 && h_coord < 11'd784) begin
            footer_row = v_coord - 10'd575;
            case ((h_coord-11'd16) >> 3)
                0:footer_char_code="F"; 1:footer_char_code="9"; 2:footer_char_code=" "; 3:footer_char_code="R"; 4:footer_char_code="E"; 5:footer_char_code="C";
                6:footer_char_code=" "; 7:footer_char_code=" "; 8:footer_char_code="E"; 9:footer_char_code="N"; 10:footer_char_code="T"; 11:footer_char_code="E"; 12:footer_char_code="R";
                13:footer_char_code=" "; 14:footer_char_code="P"; 15:footer_char_code="L"; 16:footer_char_code="A"; 17:footer_char_code="Y";
                18:footer_char_code=" "; 19:footer_char_code=" "; 20:footer_char_code="E"; 21:footer_char_code="S"; 22:footer_char_code="C"; 23:footer_char_code=" "; 24:footer_char_code="S"; 25:footer_char_code="T"; 26:footer_char_code="O"; 27:footer_char_code="P";
                28:footer_char_code=" "; 29:footer_char_code=" "; 30:footer_char_code="T"; 31:footer_char_code="A"; 32:footer_char_code="B"; 33:footer_char_code="/"; 34:footer_char_code="F"; 35:footer_char_code="1"; 36:footer_char_code="0"; 37:footer_char_code=" "; 38:footer_char_code="T"; 39:footer_char_code="R"; 40:footer_char_code="A"; 41:footer_char_code="C"; 42:footer_char_code="K";
                43:footer_char_code=" "; 44:footer_char_code=" "; 45:footer_char_code="A"; 46:footer_char_code="R"; 47:footer_char_code="R"; 48:footer_char_code="O"; 49:footer_char_code="W"; 50:footer_char_code="S"; 51:footer_char_code=" "; 52:footer_char_code="W"; 53:footer_char_code="A"; 54:footer_char_code="V"; 55:footer_char_code="E";
                default:footer_char_code=8'h20;
            endcase
        end else begin
            footer_char_code = 8'h20;
            footer_row = 3'd0;
        end
    end

endmodule
