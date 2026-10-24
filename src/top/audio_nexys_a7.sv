module audio_nexys_a7 (
  //----------- CLOCK                                            -------------//
    input   logic            CLK100MHZ ,
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

  //----------- Keyboard decoder outputs (audio domain)         -----------//
    wire [ 3:0]   keyboard_digit       ;
    wire          keyboard_digit_valid ;
    wire [ 2:0]   keyboard_note_index  ;
    wire [ 2:0]   keyboard_note_octave ;
    wire          keyboard_note_event  ;
    wire          keyboard_note_down   ;
    wire          keyboard_poly_event  ;
    wire          keyboard_poly_down   ;
    wire [ 7:0]   keyboard_poly_key    ;
    wire [ 2:0]   keyboard_poly_note_index;
    wire [ 2:0]   keyboard_poly_note_octave;
    wire [15:0]   keyboard_poly_sample ;
    wire [ 3:0]   keyboard_voice_count ;
    wire          record_toggle       ;
    wire          play_trigger        ;
    wire          play_stop            ;
    wire          track_next           ;
    wire          track_prev           ;
    wire          wave_next            ;
    wire          wave_prev            ;
    wire [ 3:0]   melody_event_valid  ;
    wire          melody_event_down   ;
    wire [ 7:0]   melody_event_key    ;
    wire [ 2:0]   melody_event_note   ;
    wire [ 2:0]   melody_event_octave ;
    wire [ 1:0]   melody_event_waveform;
    wire [ 1:0]   melody_event_waveform_by_track [0:3];
    wire [ 1:0]   synth_waveform_select;
    wire [ 3:0]   melody_recording   ;
    wire [ 3:0]   melody_playing     ;
    wire [ 6:0]   melody_event_count [0:3];
    wire [ 4:0]   melody_preview_count [0:3];
    wire [79:0]   melody_preview_notes [0:3];
    wire [895:0]  melody_roll_matrix [0:3];
    wire [ 3:0]   melody_event_down_by_track;
    wire [ 7:0]   melody_event_key_by_track [0:3];
    wire [ 2:0]   melody_event_note_by_track [0:3];
    wire [ 2:0]   melody_event_octave_by_track [0:3];
    wire [ 3:0]   melody_event_ready;
    reg  [ 1:0]   selected_track;
    reg  [ 1:0]   waveform_select;
    reg  [ 2:0]   ui_note_index_audio;
    reg  [ 1:0]   ui_note_octave_audio;
    reg           ui_note_valid_audio;
    reg  [ 1:0]   playback_grant;
    reg           playback_found;
    integer       playback_scan;
    wire          sample_tick        ;
    wire          synth_event        ;
    wire          synth_event_down   ;
    wire [ 7:0]   synth_event_key    ;
    wire [ 2:0]   synth_event_note   ;
    wire [ 2:0]   synth_event_octave ;

  //----------- Audio data path                                  -----------//
    wire [ 2:0]   audio_note_index     ;
    wire [ 2:0]   audio_note_octave    ;
    wire          audio_play           ;
    wire [15:0]   sample               ;
    wire [15:0]   local_sample         ;
    wire          valid                ;
    wire          ready                ;
    wire signed [16:0] sample_centered ;
    wire signed [21:0] vol_mult       ;
    wire signed [21:0] sample_scaled_signed;
    wire [15:0]   sample_scaled        ;
    wire [31:0]   fifo_wr_data         ;
    wire          fifo_wr_en           ;
    wire          fifo_full            ;
    wire [31:0]   fifo_rd_data         ;
    wire          fifo_rd_en           ;
    wire          fifo_empty           ;
    wire          aud_pwm_loc          ;

  //----------- Seven Segments Indicators & Safe CDC             -----------//
    reg           digit_toggle_audio   ;
    reg  [ 3:0]   digit_audio_latched  ;
    reg           track_toggle_audio  ;
    reg  [ 3:0]   track_audio_latched  ;
    reg           wave_toggle_audio   ;
    reg  [ 3:0]   wave_audio_latched  ;
    (* ASYNC_REG = "TRUE" *) reg [1:0] digit_toggle_sync;
    reg           digit_toggle_sync_d  ;
    (* ASYNC_REG = "TRUE" *) reg [1:0] track_toggle_sync;
    reg           track_toggle_sync_d  ;
    (* ASYNC_REG = "TRUE" *) reg [1:0] wave_toggle_sync;
    reg           wave_toggle_sync_d   ;
    reg  [ 3:0]   digit_display        ;
    reg  [ 3:0]   track_display        ;
    reg  [ 3:0]   wave_display         ;
    (* ASYNC_REG = "TRUE" *) reg [1:0] recording_status_sync;
    reg  [ 3:0]   recording_display    ;
    reg           keyboard_digit_seen  ;
    reg           track_display_seen   ;
    reg           wave_display_seen    ;
    wire [31:0]   sevseg_32bit_hex_val ;

  // Bundled audio->pixel UI state. Payload is held stable until the toggle
  // crosses into pixel_clk; all UI state changes occur at human input rates.
    wire [319:0]  ui_preview_notes_audio = {melody_preview_notes[3], melody_preview_notes[2], melody_preview_notes[1], melody_preview_notes[0]};
    wire [19:0]   ui_preview_counts_audio = {melody_preview_count[3], melody_preview_count[2], melody_preview_count[1], melody_preview_count[0]};
    wire [27:0]   ui_event_counts_audio = {melody_event_count[3], melody_event_count[2], melody_event_count[1], melody_event_count[0]};
    wire [895:0]  ui_roll_audio = melody_roll_matrix[selected_track];
    wire [1286:0] ui_state_live = {ui_roll_audio, ui_preview_notes_audio, ui_preview_counts_audio, ui_event_counts_audio,
                                    melody_playing, melody_recording, audio_play, volume, selected_track,
                                    waveform_select, ui_note_valid_audio, ui_note_octave_audio, ui_note_index_audio};
    reg [1286:0]  ui_state_audio;
    reg           ui_state_toggle_audio;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ui_state_toggle_sync;
    reg           ui_state_toggle_sync_d;
    reg [1286:0]  ui_state_pixel;

  //----------- VGA Controller                                   -----------//
    wire [10:0]   h_coord       ;   // pixel coordinates, 0..1055
    wire [ 9:0]   v_coord       ;   //                    0..627
    wire [ 3:0]   red, green, blue; // pixel color
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

  //------------- Keyboard decoder                               -----------//
  // Running in clk_audio eliminates multi-bit CDC crossing for audio control!
    ps2_keyboard_digit #(
      .FILTER_BITS    ( 8       ),
      .TIMEOUT_CYCLES ( 200_000 ),
      .LEGATO_STACK   ( 1       )
    ) keyboard_digit_input (
      .clk          ( clk_audio            ),
      .rst_n        ( aud_rst_n            ),
      .ps2_clk      ( PS2_CLK              ),
      .ps2_data     ( PS2_DATA             ),
      .digit        ( keyboard_digit       ),
      .digit_valid  ( keyboard_digit_valid ),
      .note_index   ( keyboard_note_index  ),
      .note_octave  ( keyboard_note_octave ),
      .note_event   ( keyboard_note_event  ),
      .note_down    ( keyboard_note_down   ),
      .poly_event   ( keyboard_poly_event ),
      .poly_down    ( keyboard_poly_down  ),
      .poly_key     ( keyboard_poly_key   ),
      .poly_note_index ( keyboard_poly_note_index ),
      .poly_note_octave( keyboard_poly_note_octave ),
      .record_toggle ( record_toggle ),
      .play_trigger  ( play_trigger  ),
      .play_stop     ( play_stop     ),
      .track_next    ( track_next    ),
      .track_prev    ( track_prev    ),
      .wave_next     ( wave_next     ),
      .wave_prev     ( wave_prev     )
    );

    // Arrows cycle sine -> triangle -> square -> saw. The audio voices switch
    // together; the selected waveform number is copied to the 7-segment domain.
    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
      if (!aud_rst_n) begin
        waveform_select <= 2'd0;
        wave_toggle_audio <= 1'b0;
        wave_audio_latched <= 4'd0;
      end else if (wave_next) begin
        waveform_select <= waveform_select + 1'b1;
        wave_audio_latched <= {2'b00, waveform_select + 1'b1};
        wave_toggle_audio <= ~wave_toggle_audio;
      end else if (wave_prev) begin
        waveform_select <= waveform_select - 1'b1;
        wave_audio_latched <= {2'b00, waveform_select - 1'b1};
        wave_toggle_audio <= ~wave_toggle_audio;
      end
    end

    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
      if (!aud_rst_n) begin
        ui_note_index_audio <= 3'd0;
        ui_note_octave_audio <= 2'd0;
        ui_note_valid_audio <= 1'b0;
        ui_state_audio <= 1287'd0;
        ui_state_toggle_audio <= 1'b0;
      end else begin
        if (keyboard_note_event) begin
          ui_note_index_audio <= keyboard_note_index;
          ui_note_octave_audio <= keyboard_note_octave[1:0];
          ui_note_valid_audio <= keyboard_note_down;
        end
        if (ui_state_live != ui_state_audio) begin
          ui_state_audio <= ui_state_live;
          ui_state_toggle_audio <= ~ui_state_toggle_audio;
        end
      end
    end

    always_ff @(posedge pixel_clk or negedge pix_rst_n) begin
      if (!pix_rst_n) begin
        ui_state_toggle_sync <= 2'b00;
        ui_state_toggle_sync_d <= 1'b0;
        ui_state_pixel <= 1287'd0;
      end else begin
        ui_state_toggle_sync <= {ui_state_toggle_sync[0], ui_state_toggle_audio};
        ui_state_toggle_sync_d <= ui_state_toggle_sync[1];
        if (ui_state_toggle_sync[1] ^ ui_state_toggle_sync_d)
          ui_state_pixel <= ui_state_audio;
      end
    end

    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
      if (!aud_rst_n)
        selected_track <= 2'd0;
      else if (!(|melody_recording) && track_next)
        selected_track <= selected_track + 1'b1;
      else if (!(|melody_recording) && track_prev)
        selected_track <= selected_track - 1'b1;
    end

    genvar track;
    generate
      for (track = 0; track < 4; track = track + 1) begin : melody_tracks
        melody_recorder #(.EVENT_DEPTH(64), .TRACK_ID(track)) recorder (
          .clk               ( clk_audio                                  ),
          .rst_n             ( aud_rst_n                                   ),
          .sample_tick       ( sample_tick                                 ),
          .record_toggle     ( record_toggle && (selected_track == track) && !(|melody_playing)),
          .play_trigger      ( play_trigger && !(|melody_recording)         ),
          .play_stop         ( play_stop                                   ),
          .key_event         ( keyboard_poly_event && (selected_track == track)),
          .key_down          ( keyboard_poly_down                          ),
          .key_id            ( keyboard_poly_key                           ),
          .note_index        ( keyboard_poly_note_index                    ),
          .note_octave       ( keyboard_poly_note_octave                   ),
          .note_waveform     ( waveform_select                             ),
          .event_ready       ( melody_event_ready[track]                   ),
          .event_valid       ( melody_event_valid[track]                   ),
          .event_down        ( melody_event_down_by_track[track]            ),
          .event_key         ( melody_event_key_by_track[track]            ),
          .event_note_index  ( melody_event_note_by_track[track]            ),
          .event_note_octave ( melody_event_octave_by_track[track]          ),
          .event_waveform    ( melody_event_waveform_by_track[track]        ),
          .recording         ( melody_recording[track]                     ),
          .playing           ( melody_playing[track]                       ),
          .event_count       ( melody_event_count[track]                   ),
          .preview_count     ( melody_preview_count[track]                  ),
          .preview_notes     ( melody_preview_notes[track]                  ),
          .roll_matrix       ( melody_roll_matrix[track]                    )
        );
      end
    endgenerate

    // Merge due events from all lanes. Live keys take priority; a sequencer
    // lane holds its event until the arbiter grants it.
    always_comb begin
      playback_grant = 2'd0;
      playback_found = 1'b0;
      for (playback_scan = 0; playback_scan < 4; playback_scan = playback_scan + 1) begin
        if (!playback_found && melody_event_valid[playback_scan]) begin
          playback_grant = playback_scan[1:0];
          playback_found = 1'b1;
        end
      end
    end

    assign melody_event_ready = {4{!keyboard_poly_event}} & (4'b0001 << playback_grant);
    assign melody_event_down = melody_event_down_by_track[playback_grant];
    assign melody_event_key = melody_event_key_by_track[playback_grant];
    assign melody_event_note = melody_event_note_by_track[playback_grant];
    assign melody_event_octave = melody_event_octave_by_track[playback_grant];
    assign melody_event_waveform = melody_event_waveform_by_track[playback_grant];

    // Live key events have priority; the recorder holds sequencer data through
    // event_ready while a simultaneous PS/2 key event is being dispatched.
    assign synth_event        = keyboard_poly_event || playback_found;
    assign synth_event_down   = keyboard_poly_event ? keyboard_poly_down : melody_event_down;
    assign synth_event_key    = keyboard_poly_event ? keyboard_poly_key : melody_event_key;
    assign synth_event_note   = keyboard_poly_event ? keyboard_poly_note_index : melody_event_note;
    assign synth_event_octave = keyboard_poly_event ? keyboard_poly_note_octave : melody_event_octave;
    assign synth_waveform_select = keyboard_poly_event ? waveform_select : melody_event_waveform;

  //------------- Keyboard Digit CDC (audio -> 5 MHz)            -----------//
  // Toggle handshake safely captures quasi-static digit values into 5 MHz domain
    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
      if (!aud_rst_n) begin
        digit_toggle_audio  <= 1'b0;
        digit_audio_latched <= 4'd0;
        track_toggle_audio <= 1'b0;
        track_audio_latched <= 4'd1;
      end else begin
        if (keyboard_digit_valid) begin
          digit_audio_latched <= keyboard_digit;
          digit_toggle_audio  <= ~digit_toggle_audio;
        end
        if (!(|melody_recording) && track_next) begin
          track_audio_latched <= (selected_track == 2'd3) ? 4'd1 : {2'b00, selected_track} + 4'd2;
          track_toggle_audio  <= ~track_toggle_audio;
        end else if (!(|melody_recording) && track_prev) begin
          track_audio_latched <= (selected_track == 2'd0) ? 4'd4 : {2'b00, selected_track};
          track_toggle_audio  <= ~track_toggle_audio;
        end
      end
    end

    always_ff @(posedge clk_5mhz0d or negedge rst_n) begin
      if (!rst_n) begin
        digit_toggle_sync   <= 2'b00;
        digit_toggle_sync_d <= 1'b0;
        track_toggle_sync   <= 2'b00;
        track_toggle_sync_d <= 1'b0;
        wave_toggle_sync    <= 2'b00;
        wave_toggle_sync_d  <= 1'b0;
        recording_status_sync <= 2'b00;
        digit_display       <= 4'd0;
        track_display       <= 4'd1;
        wave_display        <= 4'd0;
        recording_display   <= 4'd0;
        keyboard_digit_seen <= 1'b0;
        track_display_seen  <= 1'b1;
        wave_display_seen   <= 1'b1;
      end else begin
        digit_toggle_sync   <= {digit_toggle_sync[0], digit_toggle_audio};
        digit_toggle_sync_d <= digit_toggle_sync[1];
        track_toggle_sync   <= {track_toggle_sync[0], track_toggle_audio};
        track_toggle_sync_d <= track_toggle_sync[1];
        wave_toggle_sync    <= {wave_toggle_sync[0], wave_toggle_audio};
        wave_toggle_sync_d  <= wave_toggle_sync[1];
        recording_status_sync <= {recording_status_sync[0], |melody_recording};
        recording_display <= {3'b000, recording_status_sync[1]};
        if (digit_toggle_sync[1] ^ digit_toggle_sync_d) begin
          digit_display       <= digit_audio_latched;
          keyboard_digit_seen <= 1'b1;
        end
        if (track_toggle_sync[1] ^ track_toggle_sync_d) begin
          track_display <= track_audio_latched;
          track_display_seen <= 1'b1;
        end
        if (wave_toggle_sync[1] ^ wave_toggle_sync_d) begin
          wave_display <= wave_audio_latched;
          wave_display_seen <= 1'b1;
        end
      end
    end

//____________________________________________________________________________//

//------------- Seven Segments Indicators                        -------------//
  //----------- Seven Segments logic                             -----------//
    sevseg_ctrl #(
      .SCAN_DIV_BITS ( 13 )
    ) seven_segments_controller (
      .clk                    ( clk_5mhz0d                    ),
      .arst_n                 ( rst_n                         ),
      .sevseg_32bit_hex_val   ( sevseg_32bit_hex_val          ),
      .digit_mask             ( {4'b0, wave_display_seen, keyboard_digit_seen, 1'b1, track_display_seen} ),
      .seg_active_n           ( {CG, CF, CE, CD, CC, CB, CA} ),
      .don_active_n           ( DP                            ),
      .anodes                 ( AN                            )
    );
    assign sevseg_32bit_hex_val = {wave_display, digit_display, recording_display, track_display};
//____________________________________________________________________________//

//------------- Audio data path                                  -------------//
  //----------- Audio multiplexing & Tone generator              -----------//
    keyboard_poly_synth #(.VOICES(8)) keyboard_poly_synth_inst (
      .clk          ( clk_audio           ),
      .rst_n        ( aud_rst_n           ),
      .note_event   ( synth_event       ),
      .note_down    ( synth_event_down  ),
      .note_key     ( synth_event_key   ),
      .note_index   ( synth_event_note  ),
      .note_octave  ( synth_event_octave),
      .note_waveform   ( synth_waveform_select ),
      .ready        ( ready               ),
      .sample       ( keyboard_poly_sample),
      .active_count ( keyboard_voice_count)
    );

    assign audio_play        = play || (keyboard_voice_count != 0);
    assign audio_note_index  = note_index;
    assign audio_note_octave = SW[2:0];

    tone_generator tone_generator_inst (
      .clk         ( clk_audio         ),
      .rst_n       ( aud_rst_n         ),
      .note_index  ( audio_note_index  ),
      .octave_sel  ( audio_note_octave ),
      .sample      ( local_sample      ),
      .valid       ( valid             ),
      .ready       ( ready             )
    );
    assign sample = (keyboard_voice_count != 0) ? keyboard_poly_sample : local_sample;
    // Both DDS sources use unsigned PWM-domain samples with 0x8000 as silence.
    // Scale around zero, then restore the unsigned midpoint expected by pwm.
    assign sample_centered      = $signed({1'b0, sample}) - 17'sd32768;
    assign vol_mult             = sample_centered * $signed({1'b0, volume});
    assign sample_scaled_signed = vol_mult >>> 4;
    assign sample_scaled        = sample_scaled_signed[15:0] + 16'd32768;
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
      .sample_tick  ( sample_tick   ),
      .fifo_rd_data ( fifo_rd_data ),
      .fifo_rd_en   ( fifo_rd_en   ),
      .fifo_empty   ( fifo_empty   )
    );
    // open-drain output: '1' is set by the on-board pull-up to the clean analog 3.3V rail
    assign AUD_PWM = aud_pwm_loc ? 1'bz : 1'b0;
//____________________________________________________________________________//

  //------------- VGA workstation UI & Scope Buffer               -------------//
    wire [7:0] scope_rd_addr;
    wire [7:0] scope_sample;

    audio_scope_buffer scope_buffer_inst (
      .clk_audio    ( clk_audio           ),
      .aud_rst_n    ( aud_rst_n           ),
      .sample_tick  ( sample_tick         ),
      .audio_sample ( sample_scaled[15:8] ),
      .audio_play   ( audio_play          ),
      .pixel_clk    ( pixel_clk           ),
      .pix_rst_n    ( pix_rst_n           ),
      .frame_sync   ( v_sync              ),
      .scope_x      ( scope_rd_addr       ),
      .scope_sample ( scope_sample        )
    );
    vga_daw_ui workstation_ui (
      .pixel_clk  ( pixel_clk ),
      .rst_n      ( pix_rst_n ),
      .h_coord    ( h_coord   ),
      .v_coord    ( v_coord   ),
      .waveform_select ( ui_state_pixel[7:6] ),
      .selected_track  ( ui_state_pixel[9:8] ),
      .volume          ( ui_state_pixel[13:10] ),
      .audio_play      ( ui_state_pixel[14] ),
      .recording       ( ui_state_pixel[18:15] ),
      .playing         ( ui_state_pixel[22:19] ),
      .event_counts    ( ui_state_pixel[50:23] ),
      .preview_counts  ( ui_state_pixel[70:51] ),
      .preview_notes   ( ui_state_pixel[390:71] ),
      .roll_matrix     ( ui_state_pixel[1286:391] ),
      .active_note_valid ( ui_state_pixel[5] ),
      .active_note     ( ui_state_pixel[2:0] ),
      .active_octave   ( ui_state_pixel[4:3] ),
      .scope_sample    ( scope_sample        ),
      .scope_rd_addr   ( scope_rd_addr       ),
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
