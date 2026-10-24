`timescale 1ns/1ps

module tb_vga_daw_ui;

    reg        pixel_clk = 0;
    always #12.518 pixel_clk = ~pixel_clk; // ~39.941 MHz

    reg        rst_n = 1;
    reg [10:0] h_coord = 0;
    reg [9:0]  v_coord = 0;
    reg [1:0]  waveform_select = 0;
    reg [1:0]  selected_track = 0;
    reg [3:0]  volume = 4'd12;
    reg        audio_play = 0;
    reg [3:0]  recording = 0;
    reg [3:0]  playing = 0;
    reg [27:0] event_counts = 0;
    reg [19:0] preview_counts = 0;
    reg [319:0] preview_notes = 0;
    reg [447:0] roll_matrix = 0;
    reg        active_note_valid = 0;
    reg [2:0]  active_note = 0;
    reg [1:0]  active_octave = 0;
    reg [7:0]  scope_sample = 8'd128;
    wire [7:0] scope_rd_addr;

    wire [3:0] red;
    wire [3:0] green;
    wire [3:0] blue;
    wire [11:0] color = {red, green, blue};

    localparam [11:0] COLOR_BG          = 12'hFEA;
    localparam [11:0] COLOR_PANEL       = 12'hFFF;
    localparam [11:0] COLOR_INK         = 12'h111;
    localparam [11:0] COLOR_ACCENT      = 12'h06F;
    localparam [11:0] COLOR_ALERT       = 12'hF33;
    localparam [11:0] COLOR_PLAY        = 12'h094;
    localparam [11:0] COLOR_C_ROOT      = 12'hEFF;
    localparam [11:0] COLOR_SCOPE_BG    = 12'h012;
    localparam [11:0] COLOR_SCOPE_TRACE = 12'h0F9;

    vga_daw_ui dut (
        .pixel_clk          ( pixel_clk          ),
        .rst_n              ( rst_n              ),
        .h_coord            ( h_coord            ),
        .v_coord            ( v_coord            ),
        .waveform_select    ( waveform_select    ),
        .selected_track     ( selected_track     ),
        .volume             ( volume             ),
        .audio_play         ( audio_play         ),
        .recording          ( recording          ),
        .playing            ( playing            ),
        .event_counts       ( event_counts       ),
        .preview_counts     ( preview_counts     ),
        .preview_notes      ( preview_notes      ),
        .roll_matrix        ( roll_matrix        ),
        .active_note_valid  ( active_note_valid  ),
        .active_note        ( active_note        ),
        .active_octave      ( active_octave      ),
        .scope_sample       ( scope_sample       ),
        .scope_rd_addr      ( scope_rd_addr      ),
        .red                ( red                ),
        .green              ( green              ),
        .blue               ( blue               )
    );

    task check_pixel(input [10:0] x, input [9:0] y, input [11:0] expected_color, input [255:0] desc);
        begin
            h_coord = x;
            v_coord = y;
            #1;
            if (color !== expected_color) begin
                $display("FAIL [%0s] at (%0d, %0d): expected 0x%03h, got 0x%03h", desc, x, y, expected_color, color);
                $fatal(1);
            end else begin
                $display("PASS [%0s] at (%0d, %0d) = 0x%03h", desc, x, y, color);
            end
        end
    endtask

    initial begin
        $display("=================================================");
        $display("START VGA DAW UI COMPLETE TESTBENCH");
        $display("=================================================");

        rst_n = 1;
        waveform_select = 2'd0; // SINE
        selected_track = 2'd0;  // Track 1
        volume = 4'd12;
        audio_play = 0;
        recording = 4'd0;
        playing = 4'd0;
        event_counts = {7'd0, 7'd0, 7'd0, 7'd14}; // Track 1 has 14 events (0x0E)

        // Set a test note at C3 (pitch 14, step 0) in roll_matrix
        // roll_matrix bit index: pitch * 16 + step = 14 * 16 + 0 = 224
        roll_matrix[224] = 1'b1;

        #20;

        // -------------------------------------------------------------
        // TEST 1: SCREEN OUTER BORDER VERIFICATION (800x600 edges)
        // -------------------------------------------------------------
        $display("\n--- Test 1: Screen edge borders ---");
        check_pixel(11'd0,   10'd0,   COLOR_INK, "Top-Left corner (0,0)");
        check_pixel(11'd799, 10'd0,   COLOR_INK, "Top-Right corner (799,0)");
        check_pixel(11'd0,   10'd599, COLOR_INK, "Bottom-Left corner (0,599)");
        check_pixel(11'd799, 10'd599, COLOR_INK, "Bottom-Right corner (799,599)");

        // -------------------------------------------------------------
        // TEST 2: HEADER AND TRANSPORT BADGES
        // -------------------------------------------------------------
        $display("\n--- Test 2: Header and transport status ---");
        // Status Badge default: IDLE (gray 0xDDD)
        check_pixel(11'd660, 10'd20, 12'hDDD, "Status badge IDLE");

        // When playing: status badge becomes GREEN (0x094)
        playing = 4'b0001;
        #2;
        check_pixel(11'd660, 10'd20, COLOR_PLAY, "Status badge PLAY");
        playing = 4'b0000;

        // -------------------------------------------------------------
        // TEST 3: PIANO ROLL 28 NOTES SCALE AND NOTE BLOCKS
        // -------------------------------------------------------------
        $display("\n--- Test 3: Piano Roll 28 notes & cells ---");
        // Check C1 row background (pitch 0, row 27 -> Y = 92 + 27*16 = 524): should be light blue C_ROOT
        check_pixel(11'd100, 10'd528, COLOR_C_ROOT, "C1 row background tint");

        // Check our note at C3 (pitch 14, row = 27 - 14 = 13 -> Y = 92 + 13*16 = 300)
        // Step 0: X = 68..95. Cell interior X = 72, Y = 304
        check_pixel(11'd72, 10'd304, COLOR_ACCENT, "C3 Note cell active (72, 304)");

        // Non-active cell at Step 1: X = 68 + 28 + 4 = 100, Y = 304
        // Pitch 14 is C3 (a C root row), so background is COLOR_C_ROOT
        check_pixel(11'd100, 10'd304, COLOR_C_ROOT, "Empty C3 cell background");

        // Verify bounds: C-root tint and grid lines must NOT bleed outside table
        check_pixel(11'd10,  10'd528, COLOR_BG,    "Outside left of piano card is clean background");
        check_pixel(11'd66,  10'd528, COLOR_PANEL, "Gutter between keys and grid is card panel");
        check_pixel(11'd530, 10'd528, COLOR_BG,    "Gap between piano roll and right panels is clean background");

        // -------------------------------------------------------------
        // TEST 4: RED PLAYHEAD LINE AND 8-STEP WINDOW SHIFT
        // -------------------------------------------------------------
        $display("\n--- Test 4: Red Playhead line & window offset ---");
        // Activate playback
        audio_play = 1'b1;
        @(posedge pixel_clk); #1;

        // At step 0, playhead is at X = 68..69, Y = 70..539
        check_pixel(11'd68, 10'd200, COLOR_ALERT, "Red Playhead line at Step 0 (X=68)");
        check_pixel(11'd69, 10'd200, COLOR_ALERT, "Red Playhead line at Step 0 (X=69)");

        // Fast-forward playhead to step 16 to verify 8-step window shift
        dut.playhead_step = 5'd16;
        #2;
        // Window offset should now be 8
        if (dut.window_offset !== 5'd8)
            $fatal(1, "FAIL: window_offset must be 8 at step 16!");
        // Visible step should now be 16 - 8 = 8 (X = 68 + 8*28 = 292)
        check_pixel(11'd292, 10'd200, COLOR_ALERT, "Red Playhead line shifted to Col 8 (X=292)");

        audio_play = 1'b0;
        dut.playhead_step = 5'd0;
        #2;

        // -------------------------------------------------------------
        // TEST 5: COMPACT WAVE SELECTOR & LIVE OSCILLOSCOPE
        // -------------------------------------------------------------
        $display("\n--- Test 5: Wave Selector and Oscilloscope ---");
        // Wave selector: SINE button is selected (waveform_select=0) -> COLOR_ACCENT
        check_pixel(11'd560, 10'd70, COLOR_ACCENT, "SINE button selected (active)");

        // Switch to TRIANGLE (waveform_select=1)
        waveform_select = 2'd1;
        #2;
        check_pixel(11'd560, 10'd70, COLOR_PANEL, "SINE button inactive");
        check_pixel(11'd615, 10'd70, COLOR_ACCENT, "TRI button selected (active)");
        waveform_select = 2'd0;

        // Oscilloscope Screen:
        // When silence (scope_sample = 128), wave_curve_y = 210, so trace is on center zero axis
        scope_sample = 8'd128;
        #2;
        check_pixel(11'd600, 10'd210, COLOR_SCOPE_TRACE, "Scope trace on center axis during silence");
        check_pixel(11'd600, 10'd240, COLOR_SCOPE_BG,    "Scope dark CRT background");

        // When active sample (scope_sample = 168: offset +40 -> curve_y = 210 - 20 = 190)
        scope_sample = 8'd168;
        #2;
        check_pixel(11'd600, 10'd190, COLOR_SCOPE_TRACE, "Scope trace deflected to Y=190");
        check_pixel(11'd600, 10'd210, 12'h034,           "Scope zero reticle grid axis exposed under deflection");
        scope_sample = 8'd128;

        // -------------------------------------------------------------
        // TEST 6: 4-TRACK SEQUENCER MATRIX
        // -------------------------------------------------------------
        $display("\n--- Test 6: 4-Track matrix ---");
        // Track 1 (t=0) is selected (selected_track=0) -> COLOR_ACCENT (0x06F)
        // Row 0 is at Y = 344..365, X = 544..777
        check_pixel(11'd546, 10'd350, COLOR_ACCENT, "Track 1 selected row highlight");

        // Track 2 (t=1) is not selected -> COLOR_BG (0xFEA)
        // Row 1 is at Y = 370..391
        check_pixel(11'd546, 10'd375, COLOR_BG, "Track 2 unselected row background");

        // -------------------------------------------------------------
        // TEST 7: VOLUME VU METER BAR
        // -------------------------------------------------------------
        $display("\n--- Test 7: Volume VU meter bar ---");
        // volume = 12 (segments 0..11 are active, 12..15 inactive)
        // Segment 0: X = 552 + 0*14 + 4 = 556, Y = 512 -> COLOR_ACCENT
        check_pixel(11'd556, 10'd512, COLOR_ACCENT, "Volume segment 0 active");
        // Segment 14 (v=14 >= 12): X = 552 + 14*14 + 4 = 752, Y = 512 -> COLOR_PANEL
        check_pixel(11'd752, 10'd512, COLOR_PANEL, "Volume segment 14 inactive");

        // -------------------------------------------------------------
        // TEST 8: RESET STATE
        // -------------------------------------------------------------
        $display("\n--- Test 8: Reset state ---");
        rst_n = 0;
        #2;
        check_pixel(11'd0,   10'd0,   12'h000, "Reset color 0 at (0,0)");
        check_pixel(11'd72,  10'd304, 12'h000, "Reset color 0 at note cell");
        check_pixel(11'd560, 10'd75,  12'h000, "Reset color 0 at wave button");
        rst_n = 1;
        #2;
        check_pixel(11'd0,   10'd0,   COLOR_INK, "Active border restored after reset release");

        $display("\n=================================================");
        $display("ALL 8 VGA DAW UI TESTS PASSED SUCCESSFULLY!");
        $display("=================================================");
        $finish;
    end

endmodule
