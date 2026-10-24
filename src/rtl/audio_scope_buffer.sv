// 256-sample Digital Oscilloscope Capture Buffer.
// Captures live audio samples from clk_audio (48 kHz sample rate)
// and displays them stably in pixel_clk domain (VGA raster).
//
// Features:
// - Clock Domain Crossing (CDC): Port A on clk_audio, Port B on pixel_clk.
// - Hardware Auto-Trigger: triggers on rising zero-crossing (sample crossing 128)
//   for a completely jitter-free, stable oscilloscope waveform display.
// - Auto-blank to flat center line when audio_play is inactive.
// - Uses Distributed Dual-Port RAM (~4-8 LUTs, 0 BRAM).

module audio_scope_buffer (
    // Audio capture domain (clk_audio, 49.152 MHz)
    input  wire        clk_audio,
    input  wire        aud_rst_n,
    input  wire        sample_tick,        // 48 kHz strobe
    input  wire [7:0]  audio_sample,       // Unsigned 8-bit sample (128 = silence)
    input  wire        audio_play,         // 1 when sound is playing

    // VGA display domain (pixel_clk, 39.941 MHz)
    input  wire        pixel_clk,
    input  wire        pix_rst_n,
    input  wire        frame_sync,         // Pulse or level high at vertical front porch
    input  wire [7:0]  scope_x,            // X coordinate offset (0..233)
    output wire [7:0]  scope_sample        // Unsigned 8-bit sample at scope_x
);

    // Distributed Dual-Port RAM (256 x 8-bit)
    reg [7:0] ram [0:255];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 256; init_i = init_i + 1)
            ram[init_i] = 8'd128;
    end

    // CDC: Synchronize frame_sync from pixel_clk to clk_audio
    reg frame_toggle_pix;
    always_ff @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            frame_toggle_pix <= 1'b0;
        else if (frame_sync)
            frame_toggle_pix <= ~frame_toggle_pix;
    end

    reg [2:0] frame_sync_audio;
    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
        if (!aud_rst_n)
            frame_sync_audio <= 3'b000;
        else
            frame_sync_audio <= {frame_sync_audio[1:0], frame_toggle_pix};
    end

    wire new_frame_audio = frame_sync_audio[2] ^ frame_sync_audio[1];

    // Capture state machine (audio domain)
    typedef enum logic [1:0] {
        STATE_IDLE       = 2'd0,
        STATE_WAIT_TRIG  = 2'd1,
        STATE_RECORDING  = 2'd2
    } cap_state_t;

    cap_state_t state;
    reg [7:0] prev_sample;
    reg [7:0] wr_addr;
    reg [8:0] trig_timeout; // ~512 sample_ticks (~10.6 ms) timeout

    always_ff @(posedge clk_audio or negedge aud_rst_n) begin
        if (!aud_rst_n) begin
            state        <= STATE_IDLE;
            prev_sample  <= 8'd128;
            wr_addr      <= 8'd0;
            trig_timeout <= 9'd0;
        end else begin
            if (sample_tick) begin
                prev_sample <= audio_sample;

                case (state)
                    STATE_IDLE: begin
                        if (new_frame_audio) begin
                            wr_addr      <= 8'd0;
                            trig_timeout <= 9'd0;
                            if (audio_play)
                                state <= STATE_WAIT_TRIG;
                            else
                                state <= STATE_RECORDING;
                        end
                    end

                    STATE_WAIT_TRIG: begin
                        trig_timeout <= trig_timeout + 1'b1;
                        // Trigger on positive zero crossing (crossing 128 from below) or timeout
                        if (((prev_sample < 8'd128) && (audio_sample >= 8'd128)) || (trig_timeout >= 9'd480)) begin
                            wr_addr   <= 8'd1;
                            ram[8'd0] <= audio_sample;
                            state     <= STATE_RECORDING;
                        end
                    end

                    STATE_RECORDING: begin
                        ram[wr_addr] <= audio_play ? audio_sample : 8'd128;
                        if (wr_addr == 8'd255)
                            state <= STATE_IDLE;
                        else
                            wr_addr <= wr_addr + 1'b1;
                    end

                    default: state <= STATE_IDLE;
                endcase
            end else if (new_frame_audio && state == STATE_IDLE) begin
                wr_addr      <= 8'd0;
                trig_timeout <= 9'd0;
                if (audio_play)
                    state <= STATE_WAIT_TRIG;
                else
                    state <= STATE_RECORDING;
            end
        end
    end

    // Asynchronous read in pixel_clk domain (Distributed RAM)
    assign scope_sample = ram[scope_x];

endmodule
