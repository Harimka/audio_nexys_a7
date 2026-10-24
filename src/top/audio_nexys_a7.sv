module audio_nexys_a7 (
  //----------- CLOCK                                            -------------//
    input   logic            CLK100MHZ ,
    input   logic            UART_TXD_IN,
    input   logic            PS2_CLK   ,
    input   logic            PS2_DATA  ,
  //----------- Switches                                         -------------//
    input   logic  [15:0]    SW        ,
  //----------- Buttons                                          -------------//
    input   logic            BTNC      ,
    input   logic            BTNU      ,
    input   logic            BTNL      ,
    input   logic            BTNR      ,
    input   logic            BTND      ,
    input   logic            CPU_RESETN,
  //----------- Seven Segments Indicators                        -------------//
    output  logic            DP, CG, CF, CE, CD, CC, CB, CA,
    output  logic  [ 7:0]    AN        ,
  //----------- Audio                                            -------------//
    output  logic            AUD_PWM   ,
    output  logic            AUD_SD    ,
  //----------- VGA                                              -------------//
    output  logic  [ 3:0]    VGA_R     ,
    output  logic  [ 3:0]    VGA_G     ,
    output  logic  [ 3:0]    VGA_B     ,
    output  logic            VGA_HS    ,
    output  logic            VGA_VS
);

//------------- Signals declaration                              -------------//
  //----------- Clocks                                           -----------//
    wire          clk_audio    ;     // 49.15865 MHz, phase 0 degrees
    wire          clk_5mhz0d   ;     // 4.993 MHz,    phase 0 degrees
    wire          pixel_clk    ;     // 39.941 MHz,   SVGA 800x600@60 pixel clock
    wire          pll_locked   ;
    wire          pll_rst_n    ;
    wire          rst_n        ;     // reset in the 5 MHz domain
    wire          aud_rst_n    ;     // rst_n released synchronously to clk_audio
    wire          pix_rst_n    ;     // rst_n released synchronously to pixel_clk
  //----------- Buttons state                                    -----------//
    logic         button_c, button_c_d, button_c_u;
    logic         button_u, button_u_d, button_u_u;
    logic         button_d, button_d_d, button_d_u;
    logic         button_l, button_l_d, button_l_u;
    logic         button_r, button_r_d, button_r_u;
  //----------- Audio management registers                       -----------//
    reg           play        ;
    reg  [3:0]    volume      ;
    reg  [2:0]    note_index  ;
    wire [2:0]    keyboard_note_index;
    wire [2:0]    keyboard_note_octave;
    wire          keyboard_note_event;
    wire          keyboard_note_down;
    (* ASYNC_REG = "TRUE" *) reg [1:0] keyboard_event_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] keyboard_down_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] keyboard_note_index_sync1;
    (* ASYNC_REG = "TRUE" *) reg [2:0] keyboard_note_index_sync2;
    (* ASYNC_REG = "TRUE" *) reg [2:0] keyboard_note_octave_sync1;
    (* ASYNC_REG = "TRUE" *) reg [2:0] keyboard_note_octave_sync2;
    reg           keyboard_event_sync_d;
    reg           keyboard_note_gate;
    wire          keyboard_event_audio;
    wire [2:0]    audio_note_index;
    wire [2:0]    audio_note_octave;
  //----------- Audio data path                                  -----------//
    wire  [15:0]  sample        ;
    wire  [15:0]  local_sample  ;
    wire  [15:0]  midi_sample   ;
    wire          midi_gate     ;
    wire  [ 6:0]  midi_note     ;
    wire  [ 6:0]  midi_velocity ;
    wire          audio_play    ;
    wire          valid         ;
    wire          ready         ;
    wire  [19:0]  vol_mult      ;
    wire  [15:0]  sample_scaled ;
    wire  [31:0]  fifo_wr_data  ;
    wire          fifo_wr_en    ;
    wire          fifo_full     ;
    wire  [31:0]  fifo_rd_data  ;
    wire          fifo_rd_en    ;
    wire          fifo_empty    ;
    wire          aud_pwm_loc   ;
  //----------- Seven Segments Indicators                        -----------//
    wire  [31:0]  sevseg_32bit_hex_val ;
    wire  [ 3:0]  keyboard_digit       ;
    wire          keyboard_digit_valid;
    wire          keyboard_rst_n       ;
    logic         keyboard_digit_seen ;
  //----------- VGA Controller                                   -----------//
    wire  [10:0]  h_coord       ;   // pixel coordinates, 0..1055
    wire  [ 9:0]  v_coord       ;   //                    0..627
    wire  [ 3:0]  red, green, blue; // pixel color
    // Timing signals - don't touch these:
    wire          h_sync, v_sync;   // horizontal & vertical synchronization
    wire          disp_enbl     ;   // image output is allowed
//____________________________________________________________________________//

//------------- Clock & Reset                                      -----------//
  //----------- PLL                                              ---------//
    clk_wiz_0 clk_gen (
      .clk_in1  ( CLK100MHZ       ),
      .resetn   ( pll_rst_n       ),
      .clk_out1 ( clk_audio       ),  // 49.15865 MHz
      .clk_out2 ( clk_5mhz0d      ),  // 4.993 MHz
      .clk_out3 ( pixel_clk       ),  // 39.941 MHz
      .locked   ( pll_locked      )
    );

    reset_button_debouncer reset (
      .clk_100mhz   ( CLK100MHZ  ),
      .clk_5mhz     ( clk_5mhz0d ),
      .reset_button ( CPU_RESETN ),
      .pll_rst_n    ( pll_rst_n  ),
      .pll_locked   ( pll_locked ),
      .rst_n        ( rst_n      )
    );

  //----------- Reset synchronizers                              ---------//
    // rst_n comes from the 5 MHz domain, the other clocks are asynchronous to it
      reset_sync audio_reset_sync (
        .clk      ( clk_audio  ),
        .arst_n   ( rst_n      ),
        .rst_n    ( aud_rst_n  )
      );

      reset_sync pixel_reset_sync (
        .clk      ( pixel_clk  ),
        .arst_n   ( rst_n      ),
        .rst_n    ( pix_rst_n  )
      );
      reset_sync keyboard_reset_sync (
        .clk      ( clk_5mhz0d ),
        .arst_n   ( rst_n      ),
        .rst_n    ( keyboard_rst_n )
      );
//____________________________________________________________________________//

//------------- IO Pads assertions                               -------------//
  //----------- Debouncers for Buttons                           -----------//
    button_debouncer dbns_center (
      .clk         ( clk_audio  ),
      .arst_n      ( aud_rst_n  ),
      .sw_i        ( BTNC       ),
      .sw_state_o  ( button_c   ),
      .sw_down_o   ( button_c_d ),
      .sw_up_o     ( button_c_u )
    );
    button_debouncer dbns_up (
      .clk         ( clk_audio  ),
      .arst_n      ( aud_rst_n  ),
      .sw_i        ( BTNU       ),
      .sw_state_o  ( button_u   ),
      .sw_down_o   ( button_u_d ),
      .sw_up_o     ( button_u_u )
    );
    button_debouncer dbns_left (
      .clk         ( clk_audio  ),
      .arst_n      ( aud_rst_n  ),
      .sw_i        ( BTNL       ),
      .sw_state_o  ( button_l   ),
      .sw_down_o   ( button_l_d ),
      .sw_up_o     ( button_l_u )
    );
    button_debouncer dbns_right (
      .clk         ( clk_audio  ),
      .arst_n      ( aud_rst_n  ),
      .sw_i        ( BTNR       ),
      .sw_state_o  ( button_r   ),
      .sw_down_o   ( button_r_d ),
      .sw_up_o     ( button_r_u )
    );
    button_debouncer dbns_down (
      .clk         ( clk_audio  ),
      .arst_n      ( aud_rst_n  ),
      .sw_i        ( BTND       ),
      .sw_state_o  ( button_d   ),
      .sw_down_o   ( button_d_d ),
      .sw_up_o     ( button_d_u )
    );
  //------------- Control logic                                  -----------//
    button_ctrl button_ctrl_inst (
      .clk         ( clk_audio  ),
      .rst_n       ( aud_rst_n  ),
      .button_c    ( button_c_d ),
      .button_u    ( button_u_d ),
      .button_d    ( button_d_d ),
      .button_r    ( button_r_d ),
      .button_l    ( button_l_d ),
      .play        ( play       ),
      .volume      ( volume     ),
      .note_index  ( note_index )
    );

    midi_uart_receiver midi_uart_receiver_inst (
      .clk       ( clk_audio     ),
      .rst_n     ( aud_rst_n     ),
      .uart_rx   ( UART_TXD_IN   ),
      .gate      ( midi_gate     ),
      .note      ( midi_note     ),
      .velocity  ( midi_velocity )
    );

    ps2_keyboard_digit keyboard_digit_input (
      .clk          ( clk_5mhz0d          ),
      .rst_n        ( keyboard_rst_n      ),
      .ps2_clk      ( PS2_CLK             ),
      .ps2_data     ( PS2_DATA            ),
      .digit        ( keyboard_digit      ),
      .digit_valid  ( keyboard_digit_valid),
      .note_index   ( keyboard_note_index ),
      .note_octave  ( keyboard_note_octave),
      .note_event   ( keyboard_note_event ),
      .note_down    ( keyboard_note_down  )
    );

    always_ff @(posedge clk_5mhz0d or negedge keyboard_rst_n) begin
      if (!keyboard_rst_n)
        keyboard_digit_seen <= 1'b0;
      else if (keyboard_digit_valid)
        keyboard_digit_seen <= 1'b1;
    end

    // PS/2 decoding runs at 5 MHz; synchronize its event and associated data
    // into the 49 MHz audio domain before controlling the DDS/FIFO.
    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
      if (!aud_rst_n) begin
        keyboard_event_sync       <= 2'b00;
        keyboard_down_sync        <= 2'b00;
        keyboard_note_index_sync1 <= 3'b000;
        keyboard_note_index_sync2 <= 3'b000;
        keyboard_note_octave_sync1 <= 3'd3;
        keyboard_note_octave_sync2 <= 3'd3;
        keyboard_event_sync_d     <= 1'b0;
        keyboard_note_gate        <= 1'b0;
      end else begin
        keyboard_event_sync       <= {keyboard_event_sync[0], keyboard_note_event};
        keyboard_down_sync        <= {keyboard_down_sync[0], keyboard_note_down};
        keyboard_note_index_sync1 <= keyboard_note_index;
        keyboard_note_index_sync2 <= keyboard_note_index_sync1;
        keyboard_note_octave_sync1 <= keyboard_note_octave;
        keyboard_note_octave_sync2 <= keyboard_note_octave_sync1;
        keyboard_event_sync_d     <= keyboard_event_sync[1];
        if (keyboard_event_audio)
          keyboard_note_gate <= keyboard_down_sync[1];
      end
    end
    assign keyboard_event_audio = keyboard_event_sync[1] && !keyboard_event_sync_d;
    assign audio_note_index = keyboard_note_gate ? keyboard_note_index_sync2 : note_index;
    assign audio_note_octave = keyboard_note_gate ? keyboard_note_octave_sync2 : 3'd3;
//____________________________________________________________________________//

//------------- Seven Segments Indicators                        -------------//
  //----------- Seven Segments logic                             -----------//
    sevseg_ctrl seven_segments_controller (
      .clk                    ( clk_5mhz0d                    ),
      .arst_n                 ( keyboard_rst_n                ),
      .sevseg_32bit_hex_val   ( sevseg_32bit_hex_val          ),
      .digit_mask             ( keyboard_digit_seen ? 8'h01 : 8'h00 ),
      .seg_active_n           ( {CG, CF, CE, CD, CC, CB, CA} ),
      .don_active_n           ( DP                           ),
      .anodes                 ( AN                           )
    );
    assign sevseg_32bit_hex_val = {28'b0, keyboard_digit};
//____________________________________________________________________________//

//------------- Audio data path                                  -------------//
  //----------- Tone generator                                   -----------//
    tone_generator tone_generator_inst (
      .clk         ( clk_audio   ),
      .rst_n       ( aud_rst_n   ),
      .note_index  ( audio_note_index ),
      .octave_sel  ( audio_note_octave),
      .sample      ( local_sample),
      .valid       ( valid       ),
      .ready       ( ready       )
    );
    
    midi_wavetable midi_wavetable_inst (
      .clk       ( clk_audio     ),
      .rst_n     ( aud_rst_n     ),
      .gate      ( midi_gate     ),
      .note      ( midi_note     ),
      .velocity  ( midi_velocity ),
      .ready     ( ready         ),
      .sample    ( midi_sample   )
    );

    assign audio_play    = SW[15] ? midi_gate : (play || keyboard_note_gate);
    assign sample        = SW[15] ? midi_sample : local_sample;
    assign vol_mult      = sample * volume;
    assign sample_scaled = vol_mult [19:4];
  //----------- FIFO                                             -----------//
    // Tempo is set by pwm: it reads one sample per 1024 clocks (48.006 kHz);
    // the generator steps once per written sample, so the full FIFO holds
    // 256 samples = ~5.3 ms of sound (latency of note/volume/pause changes) 
    // but even student can't catch the 5.3 ms

    assign ready = audio_play && !fifo_full;

    assign fifo_wr_en   = ready;
    assign fifo_wr_data = {16'b0, sample_scaled};

    fifo fifo_inst (
      .clk     ( clk_audio    ),
      .rst_n   ( aud_rst_n    ),
      .wr_data ( fifo_wr_data ),
      .wr_en   ( fifo_wr_en   ),
      .full    ( fifo_full    ),
      .rd_data ( fifo_rd_data ),
      .rd_en   ( fifo_rd_en   ),
      .empty   ( fifo_empty   )
    );
  //----------- PWM                                              -----------//
    pwm pwm_inst (
      .clk          ( clk_audio    ),
      .rst_n        ( aud_rst_n    ),
      .aud_pwm      ( aud_pwm_loc  ),
      .aud_en       ( AUD_SD       ),
      .fifo_rd_data ( fifo_rd_data ),
      .fifo_rd_en   ( fifo_rd_en   ),
      .fifo_empty   ( fifo_empty   )
    );
    // open-drain output: '1' is set by the on-board pull-up to the clean analog 3.3V rail
    assign AUD_PWM = aud_pwm_loc ? 1'bz : 1'b0;
//____________________________________________________________________________//

//------------- VGA                                              -------------//
  //----------- Picture: Sber logo, then text                    -----------//
    vga_demo vga_demo (
      .pixel_clk  ( pixel_clk ),
      .rst_n      ( pix_rst_n ),
      .h_coord    ( h_coord   ),
      .v_coord    ( v_coord   ),
      .red        ( red       ),
      .green      ( green     ),
      .blue       ( blue      )
    );
  //----------- VGA controller (SVGA 800x600@60 timing)          -----------//
    display_ctrl display_ctrl (
      .pixel_clk  ( pixel_clk ), // Pixel clock 39.941 MHz
      .rst_n      ( pix_rst_n ), // Active low synchronous reset
      .h_sync     ( h_sync    ), // horizontal sync signal
      .v_sync     ( v_sync    ), // vertical sync signal
      .disp_enbl  ( disp_enbl ), // display enable (0 = all colors must be blank)
      .h_coord    ( h_coord   ), // horizontal pixel coordinate
      .v_coord    ( v_coord   )  // vertical pixel coordinate
    );

  //----------- VGA reg                                          -----------//
      always_ff @(posedge pixel_clk) begin
        if (disp_enbl == 1'b1) begin
          VGA_R <= red  ;
          VGA_B <= blue ;
          VGA_G <= green;
        end
        else begin
          VGA_R <= 4'd0;
          VGA_B <= 4'd0;
          VGA_G <= 4'd0;
        end
          VGA_HS <= h_sync;
          VGA_VS <= v_sync;
      end
//____________________________________________________________________________//

endmodule
