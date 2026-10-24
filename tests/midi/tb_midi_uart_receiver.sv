`timescale 1ns/1ps
module tb_midi_uart_receiver;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg uart_rx = 1;
    wire gate;
    wire [6:0] note, velocity;
    wire [15:0] sample;

    midi_uart_receiver #(.CLK_HZ(1_000_000), .BAUD(100_000)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
        .gate(gate), .note(note), .velocity(velocity)
    );
    midi_wavetable synth (
        .clk(clk), .rst_n(rst_n), .gate(gate), .note(note),
        .velocity(velocity), .ready(1'b1), .sample(sample)
    );

    task automatic send_byte(input [7:0] value);
        integer i;
        begin
            uart_rx = 0;
            repeat (10) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = value[i];
                repeat (10) @(posedge clk);
            end
            uart_rx = 1;
            repeat (12) @(posedge clk);
        end
    endtask

    reg [15:0] first_sample;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        send_byte(8'h90); // Note On, channel 1
        send_byte(8'd69);  // A4
        send_byte(8'd100); // velocity
        if (!gate || note != 69 || velocity != 100)
            $fatal(1, "Note On was not decoded");

        first_sample = sample;
        repeat (200) @(posedge clk);
        if (sample == first_sample)
            $fatal(1, "wavetable oscillator did not advance");

        send_byte(8'h80); // Note Off
        send_byte(8'd69);
        send_byte(8'd0);
        if (gate) $fatal(1, "Note Off did not silence matching note");

        // Running status: Note On omits 0x90 after the status byte.
        send_byte(8'h90);
        send_byte(8'd60);
        send_byte(8'd80);
        if (!gate || note != 60 || velocity != 80)
            $fatal(1, "running-status Note On was not decoded");

        // Note On with velocity zero is equivalent to Note Off.
        send_byte(8'h90);
        send_byte(8'd60);
        send_byte(8'd0);
        if (gate) $fatal(1, "zero-velocity Note On did not silence note");

        $display("PASS: UART MIDI Note On/Off, running status and wavetable advance");
        $finish;
    end
endmodule
