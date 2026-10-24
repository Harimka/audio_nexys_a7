// Synchronous Audio Sample ROM inferred as Block RAM (BRAM) on Artix-7.
// Stores 16-bit audio samples loaded at elaboration time via $readmemh.
// Read latency: exactly 1 clock cycle.
// Clock enable 'en' allows freezing memory output under downstream backpressure.
module audio_sample_rom #(
    parameter integer ADDR_WIDTH = 12,                      // 2^12 = 4096 samples
    parameter integer DATA_WIDTH = 16,                      // 16-bit audio words
    parameter         INIT_FILE  = "src/rtl/sample_data.mem" // Hex initialization file
) (
    input  wire                  clk,
    input  wire                  en,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] dout
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge clk) begin
        if (en) begin
            dout <= mem[addr];
        end
    end

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end
endmodule
