// Receive PS/2 Set-2 keyboard bytes, remember the last numeric key pressed,
// and emit monophonic/legato note events from keyboard rows.
// PS/2 pins are asynchronous to clk; each is synchronized and filtered.
// The PIC24 on Nexys A7 translates a supported USB HID keyboard to this PS/2
// interface. This module is receive-only and never drives either pin.
//
// Parameters:
//   FILTER_BITS: Number of clock cycles for glitch filter on PS2_CLK/PS2_DATA.
//   TIMEOUT_CYCLES: Frame timeout cycles before resetting bit counter.
//   LEGATO_STACK:
//     0 = Simple monophonic: single active key register. Release of active key
//         stops sound; release of older key is ignored.
//     1 = Held-note stack (Last-Note Priority): tracks up to MAX_HELD keys.
//         Releasing active key cleanly returns sound to previous held key.
//         Releasing older key does not interrupt active key.
module ps2_keyboard_digit #(
    parameter integer FILTER_BITS    = 8,
    parameter integer TIMEOUT_CYCLES = 200_000,
    parameter integer LEGATO_STACK   = 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg  [3:0] digit,
    output reg        digit_valid,
    output reg  [2:0] note_index,
    output reg  [2:0] note_octave,
    output reg        note_event,
    output reg        note_down
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] clk_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] data_sync;
    reg [FILTER_BITS-1:0] clk_history;
    reg [FILTER_BITS-1:0] data_history;
    reg clk_filtered, data_filtered;
    reg clk_previous;

    wire falling_edge = clk_previous && !clk_filtered;

    localparam integer TIMER_BITS = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [TIMER_BITS-1:0] age;
    reg [3:0] bit_count;
    reg [7:0] shift;
    reg parity_bit;
    reg byte_valid;
    reg [7:0] byte_data;
    reg break_prefix;
    reg extended_prefix;

    // State for simple monophonic mode (LEGATO_STACK == 0)
    reg [7:0] held_note_scan_code;
    reg       held_note_valid;

    // State for held-note stack mode (LEGATO_STACK != 0)
    localparam integer MAX_HELD = 8;
    reg [7:0] held_stack [0:MAX_HELD-1];
    reg [3:0] held_count;

    function automatic is_note_scan_code(input [7:0] scan_code);
        begin
            case (scan_code)
                // Top row 1..7: octave 1.
                8'h16, 8'h1E, 8'h26, 8'h25, 8'h2E, 8'h36, 8'h3D,
                // Q..U: octave 2.
                8'h15, 8'h1D, 8'h24, 8'h2D, 8'h2C, 8'h35, 8'h3C,
                // A..J: octave 3.
                8'h1C, 8'h1B, 8'h23, 8'h2B, 8'h34, 8'h33, 8'h3B,
                // Z..M: octave 4.
                8'h1A, 8'h22, 8'h21, 8'h2A, 8'h32, 8'h31, 8'h3A:
                    is_note_scan_code = 1'b1;
                default: is_note_scan_code = 1'b0;
            endcase
        end
    endfunction

    function automatic [2:0] note_index_for_scan(input [7:0] scan_code);
        begin
            case (scan_code)
                8'h16, 8'h15, 8'h1C, 8'h1A: note_index_for_scan = 3'd0; // C
                8'h1E, 8'h1D, 8'h1B, 8'h22: note_index_for_scan = 3'd1; // D
                8'h26, 8'h24, 8'h23, 8'h21: note_index_for_scan = 3'd2; // E
                8'h25, 8'h2D, 8'h2B, 8'h2A: note_index_for_scan = 3'd3; // F
                8'h2E, 8'h2C, 8'h34, 8'h32: note_index_for_scan = 3'd4; // G
                8'h36, 8'h35, 8'h33, 8'h31: note_index_for_scan = 3'd5; // A
                8'h3D, 8'h3C, 8'h3B, 8'h3A: note_index_for_scan = 3'd6; // B
                default: note_index_for_scan = 3'd0;
            endcase
        end
    endfunction

    function automatic [2:0] octave_for_scan(input [7:0] scan_code);
        begin
            case (scan_code)
                8'h16, 8'h1E, 8'h26, 8'h25, 8'h2E, 8'h36, 8'h3D:
                    octave_for_scan = 3'd0;
                8'h15, 8'h1D, 8'h24, 8'h2D, 8'h2C, 8'h35, 8'h3C:
                    octave_for_scan = 3'd1;
                8'h1C, 8'h1B, 8'h23, 8'h2B, 8'h34, 8'h33, 8'h3B:
                    octave_for_scan = 3'd2;
                8'h1A, 8'h22, 8'h21, 8'h2A, 8'h32, 8'h31, 8'h3A:
                    octave_for_scan = 3'd3;
                default: octave_for_scan = 3'd3;
            endcase
        end
    endfunction

    // 1. Debouncing and synchronizer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync      <= 2'b11;
            data_sync     <= 2'b11;
            clk_history   <= {FILTER_BITS{1'b1}};
            data_history  <= {FILTER_BITS{1'b1}};
            clk_filtered  <= 1'b1;
            data_filtered <= 1'b1;
            clk_previous  <= 1'b1;
        end else begin
            clk_sync     <= {clk_sync[0], ps2_clk};
            data_sync    <= {data_sync[0], ps2_data};
            clk_history  <= {clk_history[FILTER_BITS-2:0], clk_sync[1]};
            data_history <= {data_history[FILTER_BITS-2:0], data_sync[1]};

            if (&clk_history) clk_filtered <= 1'b1;
            else if (~|clk_history) clk_filtered <= 1'b0;
            if (&data_history) data_filtered <= 1'b1;
            else if (~|data_history) data_filtered <= 1'b0;

            clk_previous <= clk_filtered;
        end
    end

    // 2. PS/2 Framing FSM and Event Processing
    integer fi;
    integer si;
    integer found_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            age                 <= 0;
            bit_count           <= 0;
            shift               <= 0;
            parity_bit          <= 0;
            byte_valid          <= 1'b0;
            byte_data           <= 0;
            break_prefix        <= 1'b0;
            extended_prefix     <= 1'b0;
            held_note_scan_code <= 8'h00;
            held_note_valid     <= 1'b0;
            held_count          <= 4'd0;
            for (fi = 0; fi < MAX_HELD; fi = fi + 1) held_stack[fi] <= 8'h00;
            digit               <= 4'd0;
            digit_valid         <= 1'b0;
            note_index          <= 3'd0;
            note_octave         <= 3'd3;
            note_event          <= 1'b0;
            note_down           <= 1'b0;
        end else begin
            byte_valid  <= 1'b0;
            digit_valid <= 1'b0;
            note_event  <= 1'b0;

            if (falling_edge) begin
                age <= 0;
                case (bit_count)
                    0: begin
                        if (!data_filtered) bit_count <= 1;
                    end
                    1,2,3,4,5,6,7,8: begin
                        shift[bit_count-1] <= data_filtered;
                        bit_count <= bit_count + 1'b1;
                    end
                    9: begin
                        parity_bit <= data_filtered;
                        bit_count <= 10;
                    end
                    10: begin
                        bit_count <= 0;
                        if (data_filtered && ((^shift) ^ parity_bit)) begin
                            byte_data  <= shift;
                            byte_valid <= 1'b1;
                        end
                    end
                    default: bit_count <= 0;
                endcase
            end else if (bit_count != 0) begin
                if (age == TIMEOUT_CYCLES-1) begin
                    bit_count <= 0;
                    age <= 0;
                    break_prefix <= 1'b0;
                    extended_prefix <= 1'b0;
                end else begin
                    age <= age + 1'b1;
                end
            end else begin
                age <= 0;
            end

            if (byte_valid) begin
                if (byte_data == 8'hF0) begin
                    break_prefix <= 1'b1;
                end else if (byte_data == 8'hE0) begin
                    extended_prefix <= 1'b1;
                end else begin
                    if (!extended_prefix && break_prefix) begin
                        // Key release (Break code)
                        if (is_note_scan_code(byte_data)) begin
                            if (LEGATO_STACK == 0) begin
                                if (held_note_valid && byte_data == held_note_scan_code) begin
                                    note_event      <= 1'b1;
                                    note_down       <= 1'b0;
                                    held_note_valid <= 1'b0;
                                end
                            end else begin
                                found_pos = -1;
                                for (fi = 0; fi < MAX_HELD; fi = fi + 1) begin
                                    if (fi < held_count && held_stack[fi] == byte_data) begin
                                        found_pos = fi;
                                    end
                                end

                                if (found_pos >= 0) begin
                                    for (si = 0; si < MAX_HELD - 1; si = si + 1) begin
                                        if (si >= found_pos && si < held_count - 1) begin
                                            held_stack[si] <= held_stack[si+1];
                                        end
                                    end
                                    held_count <= held_count - 1'b1;

                                    if (found_pos == held_count - 1) begin
                                        // Released key was active top note
                                        if (held_count == 1) begin
                                            // Stack now empty
                                            note_down  <= 1'b0;
                                            note_event <= 1'b1;
                                        end else begin
                                            // Return sound to previously held key
                                            note_index  <= note_index_for_scan(held_stack[held_count - 2]);
                                            note_octave <= octave_for_scan(held_stack[held_count - 2]);
                                            note_down   <= 1'b1;
                                            note_event  <= 1'b1;
                                        end
                                    end
                                end
                            end
                        end
                    end else if (!extended_prefix) begin
                        // Key press (Make code)
                        if (is_note_scan_code(byte_data)) begin
                            if (LEGATO_STACK == 0) begin
                                // Suppress typematic repeat pulse if key is already held
                                if (!held_note_valid || byte_data != held_note_scan_code) begin
                                    note_index          <= note_index_for_scan(byte_data);
                                    note_octave         <= octave_for_scan(byte_data);
                                    note_event          <= 1'b1;
                                    note_down           <= 1'b1;
                                    held_note_scan_code <= byte_data;
                                    held_note_valid     <= 1'b1;
                                end
                            end else begin
                                if (held_count > 0 && held_stack[held_count - 1] == byte_data) begin
                                    // Typematic repeat of currently playing note: ignore
                                end else begin
                                    found_pos = -1;
                                    for (fi = 0; fi < MAX_HELD; fi = fi + 1) begin
                                        if (fi < held_count && held_stack[fi] == byte_data) begin
                                            found_pos = fi;
                                        end
                                    end

                                    if (found_pos >= 0) begin
                                        // Key was in stack lower down: move to top
                                        for (si = 0; si < MAX_HELD - 1; si = si + 1) begin
                                            if (si >= found_pos && si < held_count - 1) begin
                                                held_stack[si] <= held_stack[si + 1];
                                            end
                                        end
                                        held_stack[held_count - 1] <= byte_data;
                                    end else begin
                                        // New key: push to top
                                        if (held_count < MAX_HELD) begin
                                            held_stack[held_count] <= byte_data;
                                            held_count <= held_count + 1'b1;
                                        end else begin
                                            for (si = 0; si < MAX_HELD - 1; si = si + 1) begin
                                                held_stack[si] <= held_stack[si + 1];
                                            end
                                            held_stack[MAX_HELD - 1] <= byte_data;
                                        end
                                    end

                                    note_index  <= note_index_for_scan(byte_data);
                                    note_octave <= octave_for_scan(byte_data);
                                    note_event  <= 1'b1;
                                    note_down   <= 1'b1;
                                end
                            end
                        end

                        // Numeric row and Keypad digit decoding
                        case (byte_data)
                            // Number row, PS/2 Set 2.
                            8'h16: begin digit <= 4'd1; digit_valid <= 1'b1; end
                            8'h1E: begin digit <= 4'd2; digit_valid <= 1'b1; end
                            8'h26: begin digit <= 4'd3; digit_valid <= 1'b1; end
                            8'h25: begin digit <= 4'd4; digit_valid <= 1'b1; end
                            8'h2E: begin digit <= 4'd5; digit_valid <= 1'b1; end
                            8'h36: begin digit <= 4'd6; digit_valid <= 1'b1; end
                            8'h3D: begin digit <= 4'd7; digit_valid <= 1'b1; end
                            8'h3E: begin digit <= 4'd8; digit_valid <= 1'b1; end
                            8'h46: begin digit <= 4'd9; digit_valid <= 1'b1; end
                            8'h45: begin digit <= 4'd0; digit_valid <= 1'b1; end

                            // Numeric keypad, PS/2 Set 2.
                            8'h70: begin digit <= 4'd0; digit_valid <= 1'b1; end
                            8'h69: begin digit <= 4'd1; digit_valid <= 1'b1; end
                            8'h72: begin digit <= 4'd2; digit_valid <= 1'b1; end
                            8'h7A: begin digit <= 4'd3; digit_valid <= 1'b1; end
                            8'h6B: begin digit <= 4'd4; digit_valid <= 1'b1; end
                            8'h73: begin digit <= 4'd5; digit_valid <= 1'b1; end
                            8'h74: begin digit <= 4'd6; digit_valid <= 1'b1; end
                            8'h6C: begin digit <= 4'd7; digit_valid <= 1'b1; end
                            8'h75: begin digit <= 4'd8; digit_valid <= 1'b1; end
                            8'h7D: begin digit <= 4'd9; digit_valid <= 1'b1; end
                            default: ;
                        endcase
                    end
                    break_prefix    <= 1'b0;
                    extended_prefix <= 1'b0;
                end
            end
        end
    end
endmodule
