// step_sequencer.v - Microstep counter + sine/cosine LUT for both coils
//
// step_pul is synchronized here (2-stage FF + edge-detect register = 3 FF total).
// All other control signals (dir_s, run_hold_s, en_s, microstep_s) arrive
// pre-synchronized from input_sync — only registered here for alignment with step_cnt.
//
// LUT outputs (dac_a/b, sign_a/b) are purely combinational from step_cnt.
//
// microstep_s=1 → 16-step: ±1 per pulse, wraps 0↔15
// microstep_s=0 →  8-step: ±2 per pulse, uses even indices 0,2,4,...,14
// dir_s=0 → count UP (forward),  dir_s=1 → count DOWN (reverse)

module microstep_seq (
    input  wire       clk, rst_n,
    input  wire       step_pul,    // Step pulse (async — synced here for edge detect)
    input  wire       dir_s,       // Direction (pre-synced): 0=forward, 1=reverse
    input  wire       en_s,        // Axis enable (pre-synced)
    input  wire       microstep_s, // Microstep mode (pre-synced): 1=16-step, 0=8-step
    // LUT outputs: amplitude and direction for each coil (combinational from step_cnt)
    output wire [3:0] dac_a,
    output wire       sign_a,
    output wire [3:0] dac_b,
    output wire       sign_b
);

    // ── Microstep counter ────────────────────────────────────────
    reg [3:0] step_cnt;   // accessible via hierarchy: dut.u_core.u_ms_seq.step_cnt

    // 2-stage sync for step_pul (async input)
    wire pul_s2;
    syn_in_signal #(.STAGES(2), .WIDTH(1)) u_pul_sync (
        .clk(clk), .rst_n(rst_n),
        .async_in(step_pul),
        .sync_out(pul_s2)
    );

    // Extra register for rising-edge detection
    reg pul_s3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pul_s3 <= 1'b0;
        else        pul_s3 <= pul_s2;
    end

    wire pul_edge  = pul_s2 & ~pul_s3;               // 1-clock-wide rising-edge strobe
    wire [3:0] step_inc = microstep_s ? 4'd1 : 4'd2; // 16-step:±1, 8-step:±2

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_cnt <= 4'd0;
        end else begin

            if (pul_edge && en_s) begin
                if (dir_s) step_cnt <= step_cnt - step_inc;
                else       step_cnt <= step_cnt + step_inc;
            end
        end
    end

    // ── Sine/cosine LUT for coil A and coil B ───────────────────
    microstep_lut #(.OFFSET(4'd0)) u_lut_a (
        .step_cnt(step_cnt),
        .dac_val (dac_a),
        .sign_bit(sign_a)
    );

    microstep_lut #(.OFFSET(4'd4)) u_lut_b (
        .step_cnt(step_cnt),
        .dac_val (dac_b),
        .sign_bit(sign_b)
    );

endmodule
