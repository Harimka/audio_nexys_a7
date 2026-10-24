`timescale 1ns/1ps

module tb_vga_daw_ui;

    reg        pixel_clk = 0;
    always #12.518 pixel_clk = ~pixel_clk; // ~39.941 MHz

    reg        rst_n = 1;
    reg [10:0] h_coord = 0;
    reg [9:0]  v_coord = 0;
    wire [3:0] red;
    wire [3:0] green;
    wire [3:0] blue;
    wire [11:0] color = {red, green, blue};

    localparam [11:0] COLOR_BG      = 12'h002;
    localparam [11:0] COLOR_BORDER  = 12'h0F4;
    localparam [11:0] COLOR_CENTER  = 12'hF22;
    localparam [11:0] COLOR_ORIGIN1 = 12'h0FF;
    localparam [11:0] COLOR_ORIGIN2 = 12'hFA0;
    localparam [11:0] COLOR_TEXT    = 12'hFFF;

    vga_daw_ui dut (
        .pixel_clk          ( pixel_clk ),
        .rst_n              ( rst_n     ),
        .h_coord            ( h_coord   ),
        .v_coord            ( v_coord   ),
        .waveform_select    ( 2'b00     ),
        .selected_track     ( 2'b00     ),
        .volume             ( 4'd8      ),
        .audio_play         ( 1'b0      ),
        .recording          ( 4'd0      ),
        .playing            ( 4'd0      ),
        .event_counts       ( 28'd0     ),
        .preview_counts     ( 20'd0     ),
        .preview_notes      ( 320'd0    ),
        .roll_matrix        ( 448'd0    ),
        .active_note_valid  ( 1'b0      ),
        .active_note        ( 3'd0      ),
        .active_octave      ( 2'd0      ),
        .red                ( red       ),
        .green              ( green     ),
        .blue               ( blue      )
    );

    task check_pixel(input [10:0] x, input [9:0] y, input [11:0] expected_color, input [255:0] desc);
        begin
            h_coord = x;
            v_coord = y;
            #1; // Combinational settling
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
        $display("START VGA DAW UI TESTBENCH");
        $display("=================================================");

        rst_n = 1;

        // -----------------------------------------------------------------
        // TEST 1: SCREEN BORDER VERIFICATION (800x600 edges)
        // -----------------------------------------------------------------
        $display("\n--- Test 1: Screen edge borders ---");
        // Four corners
        check_pixel(11'd0,   10'd0,   COLOR_BORDER, "Top-Left corner (0,0)");
        check_pixel(11'd1,   10'd1,   COLOR_BORDER, "Top-Left inner corner (1,1)");
        check_pixel(11'd799, 10'd0,   COLOR_BORDER, "Top-Right corner (799,0)");
        check_pixel(11'd798, 10'd1,   COLOR_BORDER, "Top-Right inner corner (798,1)");
        check_pixel(11'd0,   10'd599, COLOR_BORDER, "Bottom-Left corner (0,599)");
        check_pixel(11'd1,   10'd598, COLOR_BORDER, "Bottom-Left inner corner (1,598)");
        check_pixel(11'd799, 10'd599, COLOR_BORDER, "Bottom-Right corner (799,599)");
        check_pixel(11'd798, 10'd598, COLOR_BORDER, "Bottom-Right inner corner (798,598)");

        // Edges at mid-screen
        check_pixel(11'd0,   10'd200, COLOR_BORDER, "Left edge (0,200)");
        check_pixel(11'd1,   10'd200, COLOR_BORDER, "Left edge (1,200)");
        check_pixel(11'd799, 10'd200, COLOR_BORDER, "Right edge (799,200)");
        check_pixel(11'd798, 10'd200, COLOR_BORDER, "Right edge (798,200)");
        check_pixel(11'd200, 10'd0,   COLOR_BORDER, "Top edge (200,0)");
        check_pixel(11'd200, 10'd1,   COLOR_BORDER, "Top edge (200,1)");
        check_pixel(11'd200, 10'd599, COLOR_BORDER, "Bottom edge (200,599)");
        check_pixel(11'd200, 10'd598, COLOR_BORDER, "Bottom edge (200,598)");

        // Just inside border at (2,2) should NOT be border
        h_coord = 11'd2;
        v_coord = 10'd2;
        #1;
        if (color === COLOR_BORDER) begin
            $fatal(1, "FAIL: pixel (2,2) must be inside the border!");
        end else begin
            $display("PASS: Pixel (2,2) is inside border, color = 0x%03h", color);
        end

        // -----------------------------------------------------------------
        // TEST 2: CENTER MARKER VERIFICATION (X=400, Y=300)
        // -----------------------------------------------------------------
        $display("\n--- Test 2: Center crosshair marker ---");
        check_pixel(11'd400, 10'd300, COLOR_CENTER, "Center pixel (400,300)");
        check_pixel(11'd399, 10'd299, COLOR_CENTER, "Center dot (399,299)");
        check_pixel(11'd401, 10'd301, COLOR_CENTER, "Center dot (401,301)");
        check_pixel(11'd400, 10'd280, COLOR_CENTER, "Center vertical crosshair arm (400,280)");
        check_pixel(11'd380, 10'd300, COLOR_CENTER, "Center horizontal crosshair arm (380,300)");
        check_pixel(11'd405, 10'd300, COLOR_CENTER, "Center target box edge (405,300)");

        // Non-center pixel
        h_coord = 11'd350;
        v_coord = 10'd300;
        #1;
        if (color === COLOR_CENTER) begin
            $fatal(1, "FAIL: pixel (350,300) should be beyond center crosshair arm!");
        end else begin
            $display("PASS: Pixel (350,300) outside center arm, color = 0x%03h", color);
        end

        // -----------------------------------------------------------------
        // TEST 3: TEXT 1X SCALE AND ANCHOR 1 VERIFICATION (X=100, Y=100)
        // -----------------------------------------------------------------
        $display("\n--- Test 3: Text 1X scale and Anchor 1 (100,100) ---");
        // Anchor marker at (100,100)
        check_pixel(11'd100, 10'd96,  COLOR_ORIGIN1, "Anchor 1 vertical tick (100,96)");
        check_pixel(11'd96,  10'd100, COLOR_ORIGIN1, "Anchor 1 horizontal tick (96,100)");

        // Line 5: "ORIGIN 1: (X=100, Y=100)"
        // First character is 'O' from X=100 to X=107, Y=100 to Y=107.
        // Glyph row 0 of 'O' is 8'b00111000:
        // col 0 (X=100): 0
        // col 1 (X=101): 0
        // col 2 (X=102): 1 -> TEXT
        // col 3 (X=103): 1 -> TEXT
        // col 4 (X=104): 1 -> TEXT
        // col 5 (X=105): 0
        check_pixel(11'd102, 10'd100, COLOR_TEXT, "Letter 'O' row 0 col 2 (102,100)");
        check_pixel(11'd103, 10'd100, COLOR_TEXT, "Letter 'O' row 0 col 3 (103,100)");
        check_pixel(11'd104, 10'd100, COLOR_TEXT, "Letter 'O' row 0 col 4 (104,100)");

        // -----------------------------------------------------------------
        // TEST 4: TEXT 2X SCALE AND ANCHOR 2 VERIFICATION (X=100, Y=180)
        // -----------------------------------------------------------------
        $display("\n--- Test 4: Text 2X scale and Anchor 2 (100,180) ---");
        check_pixel(11'd100, 10'd176, COLOR_ORIGIN2, "Anchor 2 vertical tick (100,176)");
        check_pixel(11'd96,  10'd180, COLOR_ORIGIN2, "Anchor 2 horizontal tick (96,180)");

        // Line 8: "ORIGIN 2: (X=100, Y=180)" with 2X scale.
        // First character 'O' spans X=100..115, Y=180..195.
        // Glyph row 0 is scaled to Y=180, 181.
        // col 2 is scaled to X=104, 105.
        check_pixel(11'd104, 10'd180, COLOR_TEXT, "2X letter 'O' row 0 col 2 (104,180)");
        check_pixel(11'd105, 10'd180, COLOR_TEXT, "2X letter 'O' row 0 col 2 (105,180)");
        check_pixel(11'd104, 10'd181, COLOR_TEXT, "2X letter 'O' row 0 col 2 (104,181)");
        check_pixel(11'd105, 10'd181, COLOR_TEXT, "2X letter 'O' row 0 col 2 (105,181)");

        // -----------------------------------------------------------------
        // TEST 5: RESET STATE VERIFICATION
        // -----------------------------------------------------------------
        $display("\n--- Test 5: Reset state ---");
        rst_n = 0;
        check_pixel(11'd0,   10'd0,   12'h000, "Reset color at (0,0)");
        check_pixel(11'd400, 10'd300, 12'h000, "Reset color at (400,300)");
        check_pixel(11'd102, 10'd100, 12'h000, "Reset color at (102,100)");
        rst_n = 1;
        check_pixel(11'd0,   10'd0,   COLOR_BORDER, "Active border restored after reset release");

        $display("\n=================================================");
        $display("ALL VGA DAW UI TESTS PASSED SUCCESSFULLY!");
        $display("=================================================");
        $finish;
    end

endmodule
