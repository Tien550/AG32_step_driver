// blanking_filter.v - Generic digital input blanking filter
//
// out goes HIGH only after 'in' has been continuously HIGH for
// (BLANK_CYC + 1) consecutive clock cycles.
// Counter resets immediately when 'in' goes LOW.
//
// Example @ 100 MHz, CNT_W=4, BLANK_CYC=7:
//   threshold = 8 cycles = 80 ns  →  filters glitches shorter than 80 ns

module blanking_filter #(
    parameter CNT_W     = 4,
    parameter BLANK_CYC = 7     // latch after BLANK_CYC+1 consecutive HIGH cycles
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in,     // signal to filter
    output wire out     // HIGH once 'in' sustained HIGH for BLANK_CYC+1 cycles
);

    reg [CNT_W-1:0] cnt;

    assign out = (cnt == BLANK_CYC[CNT_W-1:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= {CNT_W{1'b0}};
        else if (~in)
            cnt <= {CNT_W{1'b0}};
        else if (cnt != BLANK_CYC[CNT_W-1:0])
            cnt <= cnt + 1'b1;
    end

endmodule
