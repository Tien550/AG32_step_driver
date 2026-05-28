// dac4_vref.v - 4-bit DAC output with run/hold mode control
// Receives direct 4-bit DAC value from sine_lut (no conversion)
// Calculates hold_dac from dac_in by scaling with hold_ratio
//
// Output to R-2R ladder DAC:
//   dac_out[3] → MSB (value 8)
//   dac_out[2] →      (value 4)
//   dac_out[1] →      (value 2)
//   dac_out[0] → LSB  (value 1)
//   Vout = VCC × (dac_out / 16)

module vref_dac (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] dac_in,        // From sine_lut (direct 4-bit, 0-15)
    input  wire       run_hold,      // 1=Run (100%), 0=Hold (50%)
    output reg  [3:0] dac_out       // → 4-pin R-2R ladder
);

    // Hold mode: 50% of LUT value (floor division by 2)
    wire [3:0]  active_dac = run_hold ? dac_in : {1'b0, dac_in[3:1]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dac_out <= 4'd0;
        else
            dac_out <= active_dac;
    end

endmodule
