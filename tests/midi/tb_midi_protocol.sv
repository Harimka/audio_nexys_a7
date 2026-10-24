`timescale 1ns/1ps
module tb_midi_protocol;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [7:0] byte_data = 0;
    reg byte_valid = 0;
    wire ev, on;
    wire [3:0] ch;
    wire [6:0] note, vel;
    wire gate;
    wire [3:0] active_ch;
    wire [6:0] active_note, active_vel;
    midi_note_decoder raw_decoder (
        .clk(clk), .rst_n(rst_n), .byte_data(byte_data), .byte_valid(byte_valid),
        .event_valid(ev), .event_on(on), .event_channel(ch),
        .event_note(note), .event_velocity(vel)
    );
    midi_note_state state (
        .clk(clk), .rst_n(rst_n), .event_valid(ev), .event_on(on),
        .event_channel(ch), .event_note(note), .event_velocity(vel),
        .gate(gate), .channel(active_ch), .note(active_note), .velocity(active_vel)
    );
    reg [31:0] packet_data = 0;
    reg packet_valid = 0, event_ready = 1;
    wire packet_ready, usb_ev, usb_on, packet_error;
    wire [3:0] usb_ch;
    wire [6:0] usb_note, usb_vel;
    usb_midi_note_decoder usb_decoder (
        .clk(clk), .rst_n(rst_n), .packet_data(packet_data),
        .packet_valid(packet_valid), .packet_ready(packet_ready),
        .event_valid(usb_ev), .event_ready(event_ready), .event_on(usb_on),
        .event_channel(usb_ch), .event_note(usb_note),
        .event_velocity(usb_vel), .packet_error(packet_error)
    );
    integer raw_count = 0;
    always @(posedge clk) if (rst_n && ev) raw_count <= raw_count + 1;
    task automatic send_byte(input [7:0] b);
        @(negedge clk); byte_data = b; byte_valid = 1;
        @(negedge clk); byte_valid = 0;
    endtask
    task automatic settle;
        repeat (3) @(negedge clk);
    endtask
    task automatic packet(input [31:0] p);
        @(negedge clk); packet_data = p; packet_valid = 1;
        while (!packet_ready) @(negedge clk);
        @(negedge clk); packet_valid = 0;
    endtask
    integer n, c, count_before;
    initial begin
        // Force an actual reset edge, avoiding simulator initialization races.
        #1; rst_n = 0; #10; rst_n = 1;
        settle();
        // Actual observed MicroLab sequence: channel 0, note 48, velocity 36.
        send_byte(8'h90); send_byte(48); send_byte(36); settle();
        if (!gate || active_note != 48 || active_vel != 36 || active_ch != 0)
            $fatal(1, "observed MicroLab Note On not decoded");
        send_byte(8'h80); send_byte(48); send_byte(57); settle();
        if (gate) $fatal(1, "release velocity must not keep note active");
        // Real running status: no second 0x90; real-time inserted in pair.
        send_byte(8'h90); send_byte(50); send_byte(40);
        send_byte(52); send_byte(8'hF8); send_byte(63); settle();
        if (!gate || active_note != 52 || active_vel != 63)
            $fatal(1, "running status / interleaved real-time failed");
        // Same pitch on a different channel must not silence the active voice.
        send_byte(8'h81); send_byte(52); send_byte(0); settle();
        if (!gate) $fatal(1, "wrong channel Note Off silenced voice");
        send_byte(8'h90); send_byte(52); send_byte(0); settle();
        if (gate) $fatal(1, "zero-velocity Note On failed");
        count_before = raw_count;
        send_byte(8'h90); send_byte(60); send_byte(8'hB0);
        send_byte(1); send_byte(127); send_byte(61); send_byte(100);
        settle();
        if (raw_count != count_before) $fatal(1, "non-note status leaked stale note");
        send_byte(8'h90); send_byte(60); send_byte(8'hF0);
        send_byte(1); send_byte(2); send_byte(8'hF7); send_byte(60); send_byte(100);
        settle();
        if (raw_count != count_before) $fatal(1, "SysEx leaked note");

        // USB packing: 09 90 30 24 -> note 48, velocity 36.
        event_ready = 0;
        packet(32'h24309009);
        if (!usb_ev || !usb_on || usb_note != 48 || usb_vel != 36 || usb_ch != 0)
            $fatal(1, "USB packet layout failed");
        // Hold next packet while output is stalled: neither event may be lost.
        @(negedge clk); packet_data = 32'h39308008; packet_valid = 1;
        repeat (7) begin
            @(negedge clk);
            if (packet_ready || !usb_ev || usb_note != 48 || !usb_on || usb_vel != 36)
                $fatal(1, "backpressure changed pending event");
        end
        event_ready = 1;
        @(negedge clk); packet_valid = 0;
        if (!usb_ev || usb_on || usb_note != 48 || usb_vel != 57)
            $fatal(1, "replacement Note Off lost");
        settle();
        // Unsupported messages and another virtual cable must not emit notes.
        packet(32'h24309019); if (usb_ev) $fatal(1, "wrong cable accepted");
        packet(32'h1B01B00B); if (usb_ev) $fatal(1, "CC became note");
        packet(32'h0000F80F); if (usb_ev) $fatal(1, "real-time became note");
        packet(32'h24308009);
        if (!packet_error || usb_ev) $fatal(1, "CIN/status mismatch accepted");
        packet(32'h24809009);
        if (!packet_error || usb_ev) $fatal(1, "invalid note accepted");
        packet(32'h80309009);
        if (!packet_error || usb_ev) $fatal(1, "invalid velocity accepted");
        packet(32'h00309009);
        if (!usb_ev || usb_on) $fatal(1, "USB velocity zero not Note Off");
        // All 128 pitches, all 16 channels, edge velocity values.
        for (c = 0; c < 16; c = c + 1)
            for (n = 0; n < 128; n = n + 1) begin
                packet({8'd127, 1'b0, n[6:0], 4'h9, c[3:0], 8'h09});
                if (!usb_ev || !usb_on || usb_ch != c || usb_note != n || usb_vel != 127)
                    $fatal(1, "USB pitch/channel sweep failed");
                packet({8'd0, 1'b0, n[6:0], 4'h8, c[3:0], 8'h08});
                if (!usb_ev || usb_on || usb_ch != c || usb_note != n)
                    $fatal(1, "USB release sweep failed");
            end
        @(negedge clk); rst_n = 0;
        #1;
        if (usb_ev || gate) $fatal(1, "reset did not clear event and voice");
        $display("PASS MIDI protocol: observed MicroLab notes, running status, channels, SysEx exclusion, USB packing, backpressure, malformed packets, 4096-event sweep");
        $finish;
    end
    initial begin #1000000; $fatal(1, "protocol timeout"); end
endmodule
