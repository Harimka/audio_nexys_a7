// Audio Sample Memory Player
// Reads 16-bit PCM audio samples from on-chip Block RAM / ROM and streams them
// to the downstream audio FIFO/PWM subsystem with strict ready/valid backpressure control.
//
// Complies with AGENTS.md requirements:
//   - Clock domain: clk_audio (49.15865 MHz)
//   - Reset: rst_n (active-low)
//   - Latency-compensated synchronous BRAM interface (1-clock read latency)
//   - Safe backpressure: under !ready, BRAM enable is deasserted and sample is held
//
// Parameters:
//   ADDR_WIDTH   : Memory address bus width (default 12 -> 4096 addresses)
//   DATA_WIDTH   : Sample width in bits (default 16)
//   SAMPLE_DEPTH : Number of valid samples to play (default 4096)
//   INIT_FILE    : Hex file to populate ROM (default "src/rtl/sample_data.mem")
module audio_sample_player #(
    parameter integer ADDR_WIDTH   = 12,
    parameter integer DATA_WIDTH   = 16,
    parameter integer SAMPLE_DEPTH = 4096,
    parameter         INIT_FILE    = "src/rtl/sample_data.mem"
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  play_trigger,  // Pulse to start playback from address 0
    input  wire                  stop_cmd,      // Pulse to stop playback
    input  wire                  loop_en,       // 1 = repeat continuously, 0 = one-shot
    input  wire                  ready,         // Handshake from audio FIFO (1 = accept sample)
    output wire                  valid,         // 1 = valid sample available on sample_out
    output wire [DATA_WIDTH-1:0] sample_out,    // 16-bit audio sample (offset-binary, center=32768)
    output reg                   playing,       // Status: 1 while playing
    output reg  [ADDR_WIDTH-1:0] sample_addr,   // Current playing sample index (for visual UI)
    output wire                  playback_end   // High during the final sample of the buffer
);

    localparam [DATA_WIDTH-1:0] SILENCE_SAMPLE = {1'b1, {(DATA_WIDTH-1){1'b0}}}; // 16'h8000

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_PRE  = 2'd1;
    localparam [1:0] ST_PLAY = 2'd2;

    reg [1:0]            state;
    reg                  valid_reg;
    reg [ADDR_WIDTH-1:0] rom_addr;
    wire                 rom_en;
    wire [DATA_WIDTH-1:0] rom_dout;

    // Combinational enable ensures BRAM freezes immediately on !ready backpressure
    assign rom_en = (state == ST_IDLE && play_trigger) ||
                    (state == ST_PRE  && ready)        ||
                    (state == ST_PLAY && valid_reg && ready);

    audio_sample_rom #(
        .ADDR_WIDTH ( ADDR_WIDTH ),
        .DATA_WIDTH ( DATA_WIDTH ),
        .INIT_FILE  ( INIT_FILE  )
    ) rom_inst (
        .clk  ( clk      ),
        .en   ( rom_en   ),
        .addr ( rom_addr ),
        .dout ( rom_dout )
    );

    assign valid        = valid_reg;
    assign sample_out   = valid_reg ? rom_dout : SILENCE_SAMPLE;
    assign playback_end = (sample_addr == SAMPLE_DEPTH - 1) && valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            rom_addr     <= 0;
            sample_addr  <= 0;
            valid_reg    <= 1'b0;
            playing      <= 1'b0;
        end else begin
            if (stop_cmd) begin
                state       <= ST_IDLE;
                rom_addr    <= 0;
                sample_addr <= 0;
                valid_reg   <= 1'b0;
                playing     <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        valid_reg   <= 1'b0;
                        playing     <= 1'b0;
                        sample_addr <= 0;
                        rom_addr    <= 0;
                        if (play_trigger) begin
                            playing <= 1'b1;
                            state   <= ST_PRE;
                        end
                    end

                    ST_PRE: begin
                        // At posedge, BRAM clocked mem[0] onto rom_dout!
                        valid_reg   <= 1'b1;
                        sample_addr <= 0;
                        state       <= ST_PLAY;

                        if (ready) begin
                            rom_addr <= (SAMPLE_DEPTH > 1) ? 1 : 0;
                        end
                    end

                    ST_PLAY: begin
                        if (valid_reg && ready) begin
                            // Current sample is consumed by downstream FIFO
                            if (sample_addr == SAMPLE_DEPTH - 1) begin
                                if (loop_en) begin
                                    sample_addr <= 0;
                                    rom_addr    <= (SAMPLE_DEPTH > 1) ? 1 : 0;
                                end else begin
                                    valid_reg   <= 1'b0;
                                    playing     <= 1'b0;
                                    state       <= ST_IDLE;
                                    rom_addr    <= 0;
                                    sample_addr <= 0;
                                end
                            end else begin
                                sample_addr <= sample_addr + 1'b1;
                                if (sample_addr == SAMPLE_DEPTH - 2) begin
                                    rom_addr <= loop_en ? 0 : 0;
                                end else begin
                                    rom_addr <= rom_addr + 1'b1;
                                end
                            end
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
