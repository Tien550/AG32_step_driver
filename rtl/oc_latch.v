// oc_latch.v - Overcurrent (OC) protection latch
//
// Signal path:
//   cmp_ov_c_x (PIN_17)
//     → input_sync (2-FF, 20 ns)
//     → oc_s
//     → blanking_filter (8 cycles = 80 ns @ 100 MHz)
//     → oc_qualified
//     → oc_fault latch
//
// oc_fault latches HIGH once oc_s stays HIGH for 8 consecutive cycles.
// Chopper switching glitches (< 80 ns) are ignored.
// Clear: rst_n LOW (hardware reset only)

module oc_guard (
    input  wire clk,
    input  wire rst_n,
    input  wire oc_s,       // Pre-synced OC signal (HIGH = overcurrent)
    output reg  oc_fault
);

    wire oc_qualified;      // oc_s passed through blanking filter

    blanking_filter #(
        .CNT_W    (4),
        .BLANK_CYC(7)       // 8 cycles = 80 ns @ 100 MHz
    ) u_blank (
        .clk  (clk),
        .rst_n(rst_n),
        .in   (oc_s),
        .out  (oc_qualified)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            oc_fault <= 1'b0;
        else if (oc_qualified) oc_fault <= 1'b1;
    end

endmodule
