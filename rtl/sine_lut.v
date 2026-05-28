// sine_lut.v - 16-entry sine LUT for microstep current profile
// Stores binary 4-bit values directly (0-15); no runtime conversion.
// OFFSET parameter is fixed at elaboration time — no runtime mux, saves resources.
//   Coil A: OFFSET=0 → index = step_cnt         (no adder synthesized)
//   Coil B: OFFSET=4 → index = (step_cnt+4)%16  (90° shift)
// Output is purely combinational.
//
// NOTE: dac_out[0] (LSB) is not connected on PCB — only bits [3:1] drive the
// R-2R ladder. All values are therefore even (bit0=0) so the actual R-2R output
// matches the intended amplitude. Scale: sin(θ) × 14 → nearest even.
//   Step levels: 0, 6, 10, 12, 14  (5 distinct levels, 3-bit effective)

module microstep_lut #(parameter [3:0] OFFSET = 4'd0)(
    input  wire [3:0] step_cnt,    // LUT index from microstep_seq
    output reg  [3:0] dac_val,     // 4-bit amplitude (0-15) → R-2R Vref DAC
    output reg        sign_bit     // 0=positive half-cycle, 1=negative half-cycle
);

    wire [3:0] lut_idx = (step_cnt + OFFSET) & 4'hF;

    always @(*) begin
        case (lut_idx)
            //         angle      sin×14  → even
            4'd0:  begin dac_val = 4'd2;  sign_bit = 1'b0; end  //   0°   0.000 →  0
            4'd1:  begin dac_val = 4'd6;  sign_bit = 1'b0; end  //  22.5° 5.363 →  6
            4'd2:  begin dac_val = 4'd10; sign_bit = 1'b0; end  //  45°   9.899 → 10
            4'd3:  begin dac_val = 4'd12; sign_bit = 1'b0; end  //  67.5° 12.93 → 12
            4'd4:  begin dac_val = 4'd14; sign_bit = 1'b0; end  //  90°   14.00 → 14  (peak)
            4'd5:  begin dac_val = 4'd12; sign_bit = 1'b0; end  // 112.5° 12.93 → 12
            4'd6:  begin dac_val = 4'd10; sign_bit = 1'b0; end  // 135°   9.899 → 10
            4'd7:  begin dac_val = 4'd6;  sign_bit = 1'b0; end  // 157.5° 5.363 →  6
            4'd8:  begin dac_val = 4'd2;  sign_bit = 1'b0; end  // 180°   0.000 →  0
            4'd9:  begin dac_val = 4'd6;  sign_bit = 1'b1; end  // 202.5° 5.363 →  6
            4'd10: begin dac_val = 4'd10; sign_bit = 1'b1; end  // 225°   9.899 → 10
            4'd11: begin dac_val = 4'd12; sign_bit = 1'b1; end  // 247.5° 12.93 → 12
            4'd12: begin dac_val = 4'd14; sign_bit = 1'b1; end  // 270°   14.00 → 14  (peak)
            4'd13: begin dac_val = 4'd12; sign_bit = 1'b1; end  // 292.5° 12.93 → 12
            4'd14: begin dac_val = 4'd10; sign_bit = 1'b1; end  // 315°   9.899 → 10
            4'd15: begin dac_val = 4'd6;  sign_bit = 1'b1; end  // 337.5° 5.363 →  6
            default: begin dac_val = 4'd2; sign_bit = 1'b0; end
        endcase
    end

endmodule
