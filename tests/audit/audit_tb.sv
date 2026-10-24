`timescale 1ns/1ps

module audit_fifo;
  reg clk=0, rst_n=0, wr_en=0, rd_en=0;
  reg [31:0] wr_data=0;
  wire [31:0] rd_data;
  wire full, empty;
  fifo dut(.*);
  always #5 clk=~clk;
  reg [31:0] model[0:30000];
  integer head=0, tail=0, size=0, i;
  reg dw,dr;
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    for(i=0;i<20000;i=i+1) begin
      wr_en = (i<300) ? 1 : ((i<600) ? 0 : $urandom_range(0,1));
      rd_en = (i<300) ? 0 : ((i<600) ? 1 : $urandom_range(0,1));
      wr_data=$urandom;
      #1;
      if(full !== (size==256) || empty !== (size==0)) $fatal(1,"FIFO flags");
      dw=wr_en&&!full; dr=rd_en&&!empty;
      if(dr) begin
        if(rd_data !== model[head]) $fatal(1,"FIFO ordering");
        head=head+1;
      end
      if(dw) begin model[tail]=wr_data; tail=tail+1; end
      size=size+dw-dr;
      @(negedge clk);
    end
    $display("PASS FIFO: 20000 cycles, fill/drain, randomized simultaneous read/write, ordering");
    $finish;
  end
endmodule

module audit_audio;
  reg clk=0,rst_n=0,ready=0;
  reg [2:0] note_index=5,octave_sel=3;
  wire [15:0] sample;
  wire valid;
  tone_generator dut(.*);
  always #5 clk=~clk;
  integer i,wraps=0;
  reg [15:0] prev_sample,held;
  initial begin
    repeat(2) @(negedge clk); rst_n=1; ready=1; prev_sample=sample;
    for(i=0;i<96013;i=i+1) begin
      @(negedge clk);
      if(sample<prev_sample) wraps=wraps+1;
      prev_sample=sample;
    end
    if(wraps<879 || wraps>881) $fatal(1,"DDS A4 frequency, wraps=%0d",wraps);
    ready=0;held=sample;
    repeat(100) begin @(negedge clk); if(sample!==held) $fatal(1,"DDS backpressure"); end
    $display("PASS DDS: A4 ~440 Hz (%0d wraps in ~2 s), phase holds under backpressure",wraps);
    $finish;
  end
endmodule

module audit_pwm;
  reg clk=0,rst_n=0,fifo_empty=0;
  reg [31:0] fifo_rd_data=0;
  wire aud_pwm,fifo_rd_en;
  wire aud_en;
  wire sample_tick;
  pwm dut(.*);
  always #5 clk=~clk;
  integer i,n,highs,reads,ticks;
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    for(n=0;n<3;n=n+1) begin
      case(n) 0:fifo_rd_data=0;1:fifo_rd_data=32768;2:fifo_rd_data=65535;endcase
      repeat(1024) @(negedge clk);
      highs=0;reads=0;
      for(i=0;i<1024;i=i+1) begin
        if(aud_pwm)highs=highs+1;
        if(fifo_rd_en)reads=reads+1;
        @(negedge clk);
      end
      if(reads!=1) $fatal(1,"PWM sample period");
      if(highs!=((fifo_rd_data>>6)+1)) $fatal(1,"PWM duty");
      $display("PWM sample=%0d high_ticks=%0d/1024",fifo_rd_data,highs);
    end
    fifo_empty=1;ticks=0;
    for(i=0;i<1024;i=i+1) begin
      if(sample_tick)ticks=ticks+1;
      @(negedge clk);
    end
    if(ticks!=1)$fatal(1,"PWM sample_tick must continue with empty FIFO");
    if(aud_en!==0) $fatal(1,"PWM empty mute");
    $display("PASS PWM: period, quantization, enable on empty; zero input gives one high tick");
    $finish;
  end
endmodule

module audit_buttons;
  reg clk=0,rst_n=0,button_c=0,button_u=0,button_d=0,button_r=0,button_l=0;
  wire play;
  wire [3:0] volume;
  wire [2:0] note_index;
  button_ctrl dut(.*);
  always #5 clk=~clk;
  initial begin
    repeat(2)@(negedge clk);rst_n=1;
    if(play!==0||volume!==8||note_index!==0)$fatal(1,"Control reset");
    button_c=1;@(negedge clk);button_c=0;
    if(play!==1)$fatal(1,"Play toggle");
    button_u=1;repeat(20)@(negedge clk);button_u=0;
    if(volume!==15)$fatal(1,"Volume upper clamp");
    button_d=1;repeat(20)@(negedge clk);button_d=0;
    if(volume!==0)$fatal(1,"Volume lower clamp");
    button_r=1;repeat(7)@(negedge clk);button_r=0;
    if(note_index!==0)$fatal(1,"Note forward wrap");
    button_l=1;@(negedge clk);button_l=0;
    if(note_index!==6)$fatal(1,"Note backward wrap");
    $display("PASS BUTTON CONTROL: defaults, toggle, saturation, note wrap");$finish;
  end
endmodule

module audit_reset;
  reg clk_100mhz=0,clk_5mhz=0,reset_button=1,pll_locked=0;
  wire pll_rst_n,rst_n;
  reset_button_debouncer #(.CNT_WIDTH(4)) dut(.*);
  always #5 clk_100mhz=~clk_100mhz;
  always #100 clk_5mhz=~clk_5mhz;
  initial begin
    #2000;$display("OBSERVATION reset startup in 4-state sim: rst_n=%b (no manual reset yet)",rst_n);
    reset_button=0;#2000;reset_button=1;#2000;pll_locked=1;#2000;
    if(rst_n!==1)$fatal(1,"Reset release after lock");
    pll_locked=0;#2000;
`ifdef EXPECT_BASELINE_DEFECTS
    if(rst_n===1)$display("REPRODUCED RESET ISSUE: rst_n remains 1 after PLL lock is lost");
    else $fatal(1,"Unexpected: issue no longer reproduced");
`else
    if(rst_n===0)$display("PASS RESET: rst_n asserts to 0 synchronously when locked de-asserts");
    else $fatal(1,"FAIL: rst_n remains 1 after PLL lock is lost");
`endif
    $finish;
  end
endmodule

module audit_vga;
  reg pixel_clk=0,rst_n=0;
  wire h_sync,v_sync,disp_enbl;
  wire [10:0] h_coord;
  wire [9:0] v_coord;
  display_ctrl dut(.*);
  always #5 pixel_clk=~pixel_clk;
  integer i,de_count=0,hs_count=0,vs_count=0,de_mismatch=0,hs_mismatch=0,vs_mismatch=0;
  reg old_vs;
  initial begin
    repeat(2)@(negedge pixel_clk);rst_n=1;
    repeat(1056*628)@(negedge pixel_clk);
    old_vs=v_sync;
    for(i=0;i<1056*628;i=i+1) begin
      if(disp_enbl)de_count=de_count+1;
      if(h_sync)hs_count=hs_count+1;
      if(v_sync)vs_count=vs_count+1;
      if(disp_enbl !== (h_coord<800&&v_coord<600))de_mismatch=de_mismatch+1;
      if(h_sync !== (h_coord>=840&&h_coord<968))hs_mismatch=hs_mismatch+1;
      if(v_sync !== (v_coord>=601&&v_coord<605))vs_mismatch=vs_mismatch+1;
      if(old_vs!==v_sync)$display("VGA VS transition: x=%0d y=%0d level=%0b",h_coord,v_coord,v_sync);
      old_vs=v_sync;
      @(negedge pixel_clk);
    end
    if(de_count!=480000||de_mismatch!=0||hs_mismatch!=0||hs_count!=128*628||vs_count!=4*1056)$fatal(1,"Unexpected VGA geometry");
    $display("PASS VGA geometry: 1056x628 total, 480000 active pixels, HS=128 pixels, VS=4 lines");
`ifdef EXPECT_BASELINE_DEFECTS
    $display("REPRODUCED VGA ISSUE: VS differs from configured front porch by %0d pixel clocks/frame",vs_mismatch);
    if(vs_mismatch==0)$fatal(1,"Unexpected: issue no longer reproduced");
`else
    if(vs_mismatch!=0)$fatal(1,"FAIL VGA: VS differs from configured front porch by %0d pixel clocks/frame",vs_mismatch);
    $display("PASS VGA: Vertical front porch matches exact standard specification (vs_mismatch=0)");
`endif
    $finish;
  end
endmodule
