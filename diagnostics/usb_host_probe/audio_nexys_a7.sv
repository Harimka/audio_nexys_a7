// Standalone, passive USB-HOST/PIC24 diagnostic. No MMCM or debug IP.
// Uses the same top name as baseline in a SEPARATE Vivado project.
module audio_nexys_a7 #(
    parameter integer STARTUP_BITS = 20,
    parameter integer SCAN_BITS = 16,
    parameter integer TIMEOUT_CYCLES = 200_000
) (
    input wire CLK100MHZ, CPU_RESETN,
    input wire PS2_CLK, PS2_DATA,
    input wire [1:0] SW,
    output wire [15:0] LED,
    output reg [7:0] AN,
    output wire CA, CB, CC, CD, CE, CF, CG,
    output wire DP, AUD_PWM, AUD_SD
);
    // FPGA register initialization supplies a power-on reset even if the user
    // does not press CPU RESET; button reset also restarts the startup timer.
    reg [STARTUP_BITS-1:0] startup = 0;
    always @(posedge CLK100MHZ) begin
        if (!CPU_RESETN) startup <= 0;
        else if (!(&startup)) startup <= startup + 1'b1;
    end
    wire rst_n;
    reset_sync reset_release (
        .clk(CLK100MHZ), .arst_n(CPU_RESETN && (&startup)), .rst_n(rst_n)
    );
    (* ASYNC_REG = "TRUE" *) reg [1:0] sw_meta, sw_sync;
    always @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin sw_meta <= 0; sw_sync <= 0; end
        else begin sw_meta <= SW; sw_sync <= sw_meta; end
    end
    wire [7:0] rx_data;
    wire rx_valid, frame_error, timeout_error;
    wire clock_level, data_level, clock_change, data_change, falling_edge;
    ps2_probe_rx #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) observer (
        .clk(CLK100MHZ), .rst_n(rst_n), .ps2_clk(PS2_CLK), .ps2_data(PS2_DATA),
        .data(rx_data), .valid(rx_valid), .frame_error(frame_error),
        .timeout_error(timeout_error), .clock_level(clock_level),
        .data_level(data_level), .clock_change(clock_change),
        .data_change(data_change), .falling_edge(falling_edge)
    );
    reg [15:0] frames, edges;
    reg [7:0] errors, timeouts;
    reg [15:0] last_two;
    reg seen_clock, seen_data, seen_frame, seen_error, seen_timeout;
    reg [25:0] heartbeat;
    always @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            frames <= 0; edges <= 0; errors <= 0; timeouts <= 0; last_two <= 0;
            seen_clock <= 0; seen_data <= 0; seen_frame <= 0;
            seen_error <= 0; seen_timeout <= 0; heartbeat <= 0;
        end else begin
            heartbeat <= heartbeat + 1'b1;
            if (clock_change) seen_clock <= 1;
            if (data_change) seen_data <= 1;
            if (falling_edge && !(&edges)) edges <= edges + 1'b1;
            if (rx_valid) begin
                seen_frame <= 1;
                if (!(&frames)) frames <= frames + 1'b1;
                last_two <= {last_two[7:0], rx_data};
            end
            if (frame_error) begin
                seen_error <= 1;
                if (!(&errors)) errors <= errors + 1'b1;
            end
            if (timeout_error) begin
                seen_timeout <= 1;
                if (!(&timeouts)) timeouts <= timeouts + 1'b1;
            end
        end
    end
    // Optional interpretation only: valid PS/2 payload bytes are fed to a
    // MIDI byte parser. A decoded candidate is NOT proof of USB-MIDI support.
    wire event_valid, event_on;
    wire [3:0] event_channel, active_channel;
    wire [6:0] event_note, event_velocity, active_note, active_velocity;
    wire gate;
    midi_note_decoder decoder (
        .clk(CLK100MHZ), .rst_n(rst_n), .byte_data(rx_data), .byte_valid(rx_valid),
        .event_valid(event_valid), .event_on(event_on),
        .event_channel(event_channel), .event_note(event_note),
        .event_velocity(event_velocity)
    );
    midi_note_state voice_state (
        .clk(CLK100MHZ), .rst_n(rst_n), .event_valid(event_valid),
        .event_on(event_on), .event_channel(event_channel),
        .event_note(event_note), .event_velocity(event_velocity),
        .gate(gate), .channel(active_channel), .note(active_note),
        .velocity(active_velocity)
    );
    // Page 2 contains decimal BCD note and velocity, unlike raw hex pages.
    function automatic [11:0] decimal3(input [6:0] n);
        reg [3:0] hundreds, tens, units;
        begin
            hundreds = n / 100;
            tens = (n / 10) % 10;
            units = n % 10;
            decimal3 = {hundreds, tens, units};
        end
    endfunction
    reg [31:0] display_word;
    always @* begin
        case (sw_sync)
            2'b00: display_word = {frames, last_two};            // CCCCPPBB hex
            2'b01: display_word = {edges, errors, timeouts};     // EEEEFFTT hex
            2'b10: display_word = {{3'b0, gate}, active_channel,
                                  decimal3(active_note), decimal3(active_velocity)};
            2'b11: display_word = 32'h12345678;                 // scanner test
        endcase
    end
    reg [SCAN_BITS-1:0] scan_timer;
    reg [2:0] digit;
    reg [31:0] snapshot;
    reg [6:0] segments;
    function automatic [6:0] hex_segments(input [3:0] n);
        case(n)
            0: hex_segments=7'b1000000; 1: hex_segments=7'b1111001;
            2: hex_segments=7'b0100100; 3: hex_segments=7'b0110000;
            4: hex_segments=7'b0011001; 5: hex_segments=7'b0010010;
            6: hex_segments=7'b0000010; 7: hex_segments=7'b1111000;
            8: hex_segments=7'b0000000; 9: hex_segments=7'b0011000;
            10:hex_segments=7'b0001000; 11:hex_segments=7'b0000011;
            12:hex_segments=7'b1000110; 13:hex_segments=7'b0100001;
            14:hex_segments=7'b0000110; 15:hex_segments=7'b0001110;
        endcase
    endfunction
    // One real clock, scan enable, one coherent snapshot per display sweep.
    always @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            scan_timer <= 0; digit <= 0; snapshot <= 0;
            AN <= 8'hFF; segments <= 7'h7F;
        end else begin
            scan_timer <= scan_timer + 1'b1;
            if (&scan_timer) begin
                AN <= ~(8'b1 << digit);
                if (digit == 0) begin
                    snapshot <= display_word;
                    segments <= hex_segments(display_word[3:0]);
                end else segments <= hex_segments(snapshot[4*digit +: 4]);
                digit <= digit + 1'b1;
            end
        end
    end
    assign {CG,CF,CE,CD,CC,CB,CA} = segments;
    assign DP = 1'b1;
    assign LED = {heartbeat[25], clock_level, data_level, seen_clock,
                  seen_data, seen_frame, seen_error, seen_timeout, last_two[7:0]};
    assign AUD_PWM = 1'bz;
    assign AUD_SD = 1'b0;
endmodule
