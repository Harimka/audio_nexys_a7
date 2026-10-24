// 800x600 VGA test pattern & layout verification module.
// Renders:
// 1. Precise 2-pixel border along screen edges (X: 0..799, Y: 0..599)
// 2. Exact screen center marker (crosshair & target box at X=400, Y=300)
// 3. Test text with visual anchor markers showing exact starting coordinates:
//    - Scale 1X (8x8 px) starting at (X=100, Y=100)
//    - Scale 2X (16x16 px) starting at (X=100, Y=180)
//    - Corner coordinate tags at (0,0), (799,0), (0,599), (799,599)
//    - Center tag at (400,300)
//    - Subtle 100px reference grid
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

    // RGB444 color palette
    localparam [11:0] COLOR_BG      = 12'h002; // Deep dark navy
    localparam [11:0] COLOR_BORDER  = 12'h0F4; // Neon green border
    localparam [11:0] COLOR_CENTER  = 12'hF22; // Bright red crosshair & center
    localparam [11:0] COLOR_ORIGIN1 = 12'h0FF; // Cyan origin marker (1X)
    localparam [11:0] COLOR_ORIGIN2 = 12'hFA0; // Orange origin marker (2X)
    localparam [11:0] COLOR_GRID    = 12'h114; // Subtle 100px dotted grid
    localparam [11:0] COLOR_TEXT    = 12'hFFF; // Crisp white text

    // Text engine signals
    reg  [3:0] text_line_id;
    reg  [5:0] char_index;
    reg  [2:0] font_row;
    reg  [2:0] font_col;
    reg        in_text_area;
    reg  [7:0] char_code;
    wire [7:0] glyph_bits;
    wire       text_pixel;

    // Feature detection flags
    reg is_border;
    reg is_center_cross;
    reg is_center_box;
    reg is_center_dot;
    reg is_origin1_marker;
    reg is_origin1_guide;
    reg is_origin2_marker;
    reg is_origin2_guide;
    reg is_grid_point;

    reg [11:0] pixel_color;

    // Text strings definition function
    function automatic [7:0] get_char_code(input [3:0] line_id, input [5:0] idx);
        begin
            case (line_id)
                // Line 0: Top-left tag "(0, 0)"
                4'd0: case (idx)
                    0: get_char_code = "("; 1: get_char_code = "0"; 2: get_char_code = ",";
                    3: get_char_code = " "; 4: get_char_code = "0"; 5: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 1: Top-right tag "(799, 0)"
                4'd1: case (idx)
                    0: get_char_code = "("; 1: get_char_code = "7"; 2: get_char_code = "9"; 3: get_char_code = "9";
                    4: get_char_code = ","; 5: get_char_code = " "; 6: get_char_code = "0"; 7: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 2: Bottom-left tag "(0, 599)"
                4'd2: case (idx)
                    0: get_char_code = "("; 1: get_char_code = "0"; 2: get_char_code = ","; 3: get_char_code = " ";
                    4: get_char_code = "5"; 5: get_char_code = "9"; 6: get_char_code = "9"; 7: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 3: Bottom-right tag "(799, 599)"
                4'd3: case (idx)
                    0: get_char_code = "("; 1: get_char_code = "7"; 2: get_char_code = "9"; 3: get_char_code = "9";
                    4: get_char_code = ","; 5: get_char_code = " "; 6: get_char_code = "5"; 7: get_char_code = "9";
                    8: get_char_code = "9"; 9: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 4: Center label "CENTER: (X=400, Y=300)"
                4'd4: case (idx)
                    0: get_char_code = "C"; 1: get_char_code = "E"; 2: get_char_code = "N"; 3: get_char_code = "T";
                    4: get_char_code = "E"; 5: get_char_code = "R"; 6: get_char_code = ":"; 7: get_char_code = " ";
                    8: get_char_code = "("; 9: get_char_code = "X"; 10: get_char_code = "="; 11: get_char_code = "4";
                    12: get_char_code = "0"; 13: get_char_code = "0"; 14: get_char_code = ","; 15: get_char_code = " ";
                    16: get_char_code = "Y"; 17: get_char_code = "="; 18: get_char_code = "3"; 19: get_char_code = "0";
                    20: get_char_code = "0"; 21: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 5: Origin 1 header "ORIGIN 1: (X=100, Y=100)"
                4'd5: case (idx)
                    0: get_char_code = "O"; 1: get_char_code = "R"; 2: get_char_code = "I"; 3: get_char_code = "G";
                    4: get_char_code = "I"; 5: get_char_code = "N"; 6: get_char_code = " "; 7: get_char_code = "1";
                    8: get_char_code = ":"; 9: get_char_code = " "; 10: get_char_code = "("; 11: get_char_code = "X";
                    12: get_char_code = "="; 13: get_char_code = "1"; 14: get_char_code = "0"; 15: get_char_code = "0";
                    16: get_char_code = ","; 17: get_char_code = " "; 18: get_char_code = "Y"; 19: get_char_code = "=";
                    20: get_char_code = "1"; 21: get_char_code = "0"; 22: get_char_code = "0"; 23: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 6: Scale 1X description "TEXT MODULE: 8X8 SCALE 1X"
                4'd6: case (idx)
                    0: get_char_code = "T"; 1: get_char_code = "E"; 2: get_char_code = "X"; 3: get_char_code = "T";
                    4: get_char_code = " "; 5: get_char_code = "M"; 6: get_char_code = "O"; 7: get_char_code = "D";
                    8: get_char_code = "U"; 9: get_char_code = "L"; 10: get_char_code = "E"; 11: get_char_code = ":";
                    12: get_char_code = " "; 13: get_char_code = "8"; 14: get_char_code = "X"; 15: get_char_code = "8";
                    16: get_char_code = " "; 17: get_char_code = "S"; 18: get_char_code = "C"; 19: get_char_code = "A";
                    20: get_char_code = "L"; 21: get_char_code = "E"; 22: get_char_code = " "; 23: get_char_code = "1";
                    24: get_char_code = "X";
                    default: get_char_code = " ";
                endcase

                // Line 7: Charset verification "CHARSET: ABC 0123 !/:.,=-"
                4'd7: case (idx)
                    0: get_char_code = "C"; 1: get_char_code = "H"; 2: get_char_code = "A"; 3: get_char_code = "R";
                    4: get_char_code = "S"; 5: get_char_code = "E"; 6: get_char_code = "T"; 7: get_char_code = ":";
                    8: get_char_code = " "; 9: get_char_code = "A"; 10: get_char_code = "B"; 11: get_char_code = "C";
                    12: get_char_code = " "; 13: get_char_code = "0"; 14: get_char_code = "1"; 15: get_char_code = "2";
                    16: get_char_code = "3"; 17: get_char_code = " "; 18: get_char_code = "!"; 19: get_char_code = "/";
                    20: get_char_code = ":"; 21: get_char_code = "."; 22: get_char_code = ","; 23: get_char_code = "=";
                    24: get_char_code = "-";
                    default: get_char_code = " ";
                endcase

                // Line 8: Origin 2 header (2X scale) "ORIGIN 2: (X=100, Y=180)"
                4'd8: case (idx)
                    0: get_char_code = "O"; 1: get_char_code = "R"; 2: get_char_code = "I"; 3: get_char_code = "G";
                    4: get_char_code = "I"; 5: get_char_code = "N"; 6: get_char_code = " "; 7: get_char_code = "2";
                    8: get_char_code = ":"; 9: get_char_code = " "; 10: get_char_code = "("; 11: get_char_code = "X";
                    12: get_char_code = "="; 13: get_char_code = "1"; 14: get_char_code = "0"; 15: get_char_code = "0";
                    16: get_char_code = ","; 17: get_char_code = " "; 18: get_char_code = "Y"; 19: get_char_code = "=";
                    20: get_char_code = "1"; 21: get_char_code = "8"; 22: get_char_code = "0"; 23: get_char_code = ")";
                    default: get_char_code = " ";
                endcase

                // Line 9: Scale 2X description "BIG TEXT: 16X16 SCALE 2X"
                4'd9: case (idx)
                    0: get_char_code = "B"; 1: get_char_code = "I"; 2: get_char_code = "G"; 3: get_char_code = " ";
                    4: get_char_code = "T"; 5: get_char_code = "E"; 6: get_char_code = "X"; 7: get_char_code = "T";
                    8: get_char_code = ":"; 9: get_char_code = " "; 10: get_char_code = "1"; 11: get_char_code = "6";
                    12: get_char_code = "X"; 13: get_char_code = "1"; 14: get_char_code = "6"; 15: get_char_code = " ";
                    16: get_char_code = "S"; 17: get_char_code = "C"; 18: get_char_code = "A"; 19: get_char_code = "L";
                    20: get_char_code = "E"; 21: get_char_code = " "; 22: get_char_code = "2"; 23: get_char_code = "X";
                    default: get_char_code = " ";
                endcase

                // Line 10: Bottom footer "VGA 800X600 COORDINATES TEST"
                4'd10: case (idx)
                    0: get_char_code = "V"; 1: get_char_code = "G"; 2: get_char_code = "A"; 3: get_char_code = " ";
                    4: get_char_code = "8"; 5: get_char_code = "0"; 6: get_char_code = "0"; 7: get_char_code = "X";
                    8: get_char_code = "6"; 9: get_char_code = "0"; 10: get_char_code = "0"; 11: get_char_code = " ";
                    12: get_char_code = "C"; 13: get_char_code = "O"; 14: get_char_code = "O"; 15: get_char_code = "R";
                    16: get_char_code = "D"; 17: get_char_code = "I"; 18: get_char_code = "N"; 19: get_char_code = "A";
                    20: get_char_code = "T"; 21: get_char_code = "E"; 22: get_char_code = "S"; 23: get_char_code = " ";
                    24: get_char_code = "T"; 25: get_char_code = "E"; 26: get_char_code = "S"; 27: get_char_code = "T";
                    default: get_char_code = " ";
                endcase

                default: get_char_code = " ";
            endcase
        end
    endfunction

    // Font ROM instance
    font_rom text_font_rom (
        .char_code ( char_code  ),
        .row       ( font_row   ),
        .bits      ( glyph_bits )
    );

    assign text_pixel = in_text_area ? glyph_bits[3'd7 - font_col] : 1'b0;

    // Text mapping and raster scanning logic
    always_comb begin
        in_text_area = 1'b0;
        text_line_id = 4'd15;
        char_index   = 6'd0;
        font_row     = 3'd0;
        font_col     = 3'd0;

        // Line 0: Top-left tag "(0, 0)" at X=8, Y=8 (len 6, width 48)
        if (v_coord >= 10'd8 && v_coord < 10'd16 && h_coord >= 11'd8 && h_coord < 11'd56) begin
            in_text_area = 1'b1;
            text_line_id = 4'd0;
            char_index   = (h_coord - 11'd8) >> 3;
            font_row     = v_coord - 10'd8;
            font_col     = (h_coord - 11'd8) & 3'b111;
        end
        // Line 1: Top-right tag "(799, 0)" at X=728, Y=8 (len 8, width 64)
        else if (v_coord >= 10'd8 && v_coord < 10'd16 && h_coord >= 11'd728 && h_coord < 11'd792) begin
            in_text_area = 1'b1;
            text_line_id = 4'd1;
            char_index   = (h_coord - 11'd728) >> 3;
            font_row     = v_coord - 10'd8;
            font_col     = (h_coord - 11'd728) & 3'b111;
        end
        // Line 2: Bottom-left tag "(0, 599)" at X=8, Y=584 (len 8, width 64)
        else if (v_coord >= 10'd584 && v_coord < 10'd592 && h_coord >= 11'd8 && h_coord < 11'd72) begin
            in_text_area = 1'b1;
            text_line_id = 4'd2;
            char_index   = (h_coord - 11'd8) >> 3;
            font_row     = v_coord - 10'd584;
            font_col     = (h_coord - 11'd8) & 3'b111;
        end
        // Line 3: Bottom-right tag "(799, 599)" at X=712, Y=584 (len 10, width 80)
        else if (v_coord >= 10'd584 && v_coord < 10'd592 && h_coord >= 11'd712 && h_coord < 11'd792) begin
            in_text_area = 1'b1;
            text_line_id = 4'd3;
            char_index   = (h_coord - 11'd712) >> 3;
            font_row     = v_coord - 10'd584;
            font_col     = (h_coord - 11'd712) & 3'b111;
        end
        // Line 4: Center tag "CENTER: (X=400, Y=300)" at X=316, Y=340 (len 22, width 176)
        else if (v_coord >= 10'd340 && v_coord < 10'd348 && h_coord >= 11'd316 && h_coord < 11'd492) begin
            in_text_area = 1'b1;
            text_line_id = 4'd4;
            char_index   = (h_coord - 11'd316) >> 3;
            font_row     = v_coord - 10'd340;
            font_col     = (h_coord - 11'd316) & 3'b111;
        end
        // Line 5: Origin 1 header "ORIGIN 1: (X=100, Y=100)" at X=100, Y=100 (len 24, width 192)
        else if (v_coord >= 10'd100 && v_coord < 10'd108 && h_coord >= 11'd100 && h_coord < 11'd292) begin
            in_text_area = 1'b1;
            text_line_id = 4'd5;
            char_index   = (h_coord - 11'd100) >> 3;
            font_row     = v_coord - 10'd100;
            font_col     = (h_coord - 11'd100) & 3'b111;
        end
        // Line 6: "TEXT MODULE: 8X8 SCALE 1X" at X=100, Y=116 (len 25, width 200)
        else if (v_coord >= 10'd116 && v_coord < 10'd124 && h_coord >= 11'd100 && h_coord < 11'd300) begin
            in_text_area = 1'b1;
            text_line_id = 4'd6;
            char_index   = (h_coord - 11'd100) >> 3;
            font_row     = v_coord - 10'd116;
            font_col     = (h_coord - 11'd100) & 3'b111;
        end
        // Line 7: "CHARSET: ABC 0123 !/:.,=-" at X=100, Y=132 (len 25, width 200)
        else if (v_coord >= 10'd132 && v_coord < 10'd140 && h_coord >= 11'd100 && h_coord < 11'd300) begin
            in_text_area = 1'b1;
            text_line_id = 4'd7;
            char_index   = (h_coord - 11'd100) >> 3;
            font_row     = v_coord - 10'd132;
            font_col     = (h_coord - 11'd100) & 3'b111;
        end
        // Line 8: Scale 2X (16x16 px) "ORIGIN 2: (X=100, Y=180)" at X=100, Y=180 (len 24, width 384, height 16)
        else if (v_coord >= 10'd180 && v_coord < 10'd196 && h_coord >= 11'd100 && h_coord < 11'd484) begin
            in_text_area = 1'b1;
            text_line_id = 4'd8;
            char_index   = (h_coord - 11'd100) >> 4;
            font_row     = (v_coord - 10'd180) >> 1;
            font_col     = ((h_coord - 11'd100) >> 1) & 3'b111;
        end
        // Line 9: Scale 2X "BIG TEXT: 16X16 SCALE 2X" at X=100, Y=204 (len 24, width 384, height 16)
        else if (v_coord >= 10'd204 && v_coord < 10'd220 && h_coord >= 11'd100 && h_coord < 11'd484) begin
            in_text_area = 1'b1;
            text_line_id = 4'd9;
            char_index   = (h_coord - 11'd100) >> 4;
            font_row     = (v_coord - 10'd204) >> 1;
            font_col     = ((h_coord - 11'd100) >> 1) & 3'b111;
        end
        // Line 10: Footer tag at X=288, Y=550 (len 28, width 224)
        else if (v_coord >= 10'd550 && v_coord < 10'd558 && h_coord >= 11'd288 && h_coord < 11'd512) begin
            in_text_area = 1'b1;
            text_line_id = 4'd10;
            char_index   = (h_coord - 11'd288) >> 3;
            font_row     = v_coord - 10'd550;
            font_col     = (h_coord - 11'd288) & 3'b111;
        end

        char_code = get_char_code(text_line_id, char_index);
    end

    // Geometry markers and pixel compositor
    always_comb begin
        // 1. Screen edge 2-pixel border
        is_border = (h_coord <= 11'd1 || h_coord >= 11'd798 || v_coord <= 10'd1 || v_coord >= 10'd598);

        // 2. Center marker at X=400, Y=300
        // Crosshair: horizontal line (X: 370..430, Y=300), vertical line (X=400, Y: 270..330)
        is_center_cross = (v_coord == 10'd300 && h_coord >= 11'd370 && h_coord <= 11'd430) ||
                          (h_coord == 11'd400 && v_coord >= 10'd270 && v_coord <= 10'd330);
        // Target box 11x11 around center
        is_center_box   = ((h_coord == 11'd395 || h_coord == 11'd405) && v_coord >= 10'd295 && v_coord <= 10'd305) ||
                          ((v_coord == 10'd295 || v_coord == 10'd305) && h_coord >= 11'd395 && h_coord <= 11'd405);
        // 3x3 solid center dot
        is_center_dot   = (h_coord >= 11'd399 && h_coord <= 11'd401 && v_coord >= 10'd299 && v_coord <= 10'd301);

        // 3. Anchor 1 marker at (X=100, Y=100)
        is_origin1_marker = ((h_coord >= 11'd96 && h_coord <= 11'd104 && v_coord == 10'd100) ||
                             (v_coord >= 10'd96 && v_coord <= 10'd104 && h_coord == 11'd100) ||
                             (h_coord >= 11'd98 && h_coord <= 11'd102 && (v_coord == 10'd98 || v_coord == 10'd102)) ||
                             (v_coord >= 10'd98 && v_coord <= 10'd102 && (h_coord == 11'd98 || h_coord == 11'd102)));
        // Dotted guide lines extending from (100, 100)
        is_origin1_guide  = ((h_coord == 11'd100 && v_coord >= 10'd80 && v_coord <= 10'd160 && (v_coord & 10'd4) == 0) ||
                             (v_coord == 10'd100 && h_coord >= 11'd60 && h_coord <= 11'd320 && (h_coord & 11'd4) == 0));

        // 4. Anchor 2 marker at (X=100, Y=180)
        is_origin2_marker = ((h_coord >= 11'd96 && h_coord <= 11'd104 && v_coord == 10'd180) ||
                             (v_coord >= 10'd176 && v_coord <= 10'd184 && h_coord == 11'd100) ||
                             (h_coord >= 11'd98 && h_coord <= 11'd102 && (v_coord == 10'd178 || v_coord == 10'd182)) ||
                             (v_coord >= 10'd178 && v_coord <= 10'd182 && (h_coord == 11'd98 || h_coord == 11'd102)));
        is_origin2_guide  = ((h_coord == 11'd100 && v_coord >= 10'd165 && v_coord <= 10'd230 && (v_coord & 10'd4) == 0) ||
                             (v_coord == 10'd180 && h_coord >= 11'd60 && h_coord <= 11'd500 && (h_coord & 11'd4) == 0));

        // 5. Subtle background grid every 100px (dotted pixel every 8 px)
        is_grid_point = ((h_coord % 11'd100 == 0 && (v_coord & 10'd7) == 0) ||
                         (v_coord % 10'd100 == 0 && (h_coord & 11'd7) == 0));

        // Priority composition
        pixel_color = COLOR_BG;

        if (is_grid_point)
            pixel_color = COLOR_GRID;

        if (is_origin1_guide)
            pixel_color = 12'h034;
        if (is_origin2_guide)
            pixel_color = 12'h320;

        if (is_origin1_marker)
            pixel_color = COLOR_ORIGIN1;
        if (is_origin2_marker)
            pixel_color = COLOR_ORIGIN2;

        if (is_center_cross || is_center_box || is_center_dot)
            pixel_color = COLOR_CENTER;

        if (text_pixel)
            pixel_color = COLOR_TEXT;

        if (is_border)
            pixel_color = COLOR_BORDER;

        if (!rst_n)
            pixel_color = 12'h000;

        {red, green, blue} = pixel_color;
    end

endmodule
