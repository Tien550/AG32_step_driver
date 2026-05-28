// stepper_axis.v - 2-coil stepper axis core (coil A = sine, coil B = cosine)
//
// Receives pre-synchronized control and comparator signals from input_sync.
// step_pul is the only async input — synchronized inside microstep_seq
// together with the rising-edge detect logic and sine/cosine LUT.
//
// Shared chopper timer generates chop_start_a (cnt==0) and
// chop_start_b (cnt==period/2), interleaving coil switching events
// to reduce simultaneous inrush current.

module axis_core (
    input  wire        clk, rst_n,
    // Step pulse — async, synchronized inside microstep_seq
    input  wire        step_pul,
    // Control signals — pre-synchronized by input_sync
    input  wire        en_s,
    input  wire        dir_s,
    input  wire        run_hold_s,
    input  wire        microstep_s,
    // Chopper comparators — pre-synchronized by input_sync (active LOW)
    input  wire        cmp_a_s,
    input  wire        cmp_b_s,
    // Timing/config from AHB registers (shared by both coils)
    input  wire [7:0]  dead_cycles,
    input  wire [11:0] fast_cycles, slow_cycles, period_cycles,
    // Coil A gate outputs (→ IRS2111S IN pins)
    output wire        q1_a,
    output wire        q3_a,
    output wire [3:0]  dac_a_out,
    // Coil B gate outputs (→ IRS2111S IN pins)
    output wire        q1_b,
    output wire        q3_b,
    output wire [3:0]  dac_b_out
);

    wire [3:0] dac_a, dac_b;     // raw LUT amplitudes — also accessible via hierarchy
    wire       sign_a, sign_b;
    wire       chop_start_a, chop_start_b;

    // Shared chopper timer: chop_start_a at cnt==0, chop_start_b at cnt==period/2
    chop_timer u_chop (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en_s),
        .period_cycles(period_cycles),
        .cycle_start_a(chop_start_a),
        .cycle_start_b(chop_start_b)
    );

    // Microstep counter + sine/cosine LUT (step_pul sync + edge detect inside)
    microstep_seq u_ms_seq (
        .clk        (clk),
        .rst_n      (rst_n),
        .step_pul   (step_pul),
        .dir_s      (dir_s),
        .en_s       (en_s),
        .microstep_s(microstep_s),
        .dac_a      (dac_a),
        .sign_a     (sign_a),
        .dac_b      (dac_b),
        .sign_b     (sign_b)
    );

    // Coil A driver
    coil_drv u_coil_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en_s),
        .cycle_start  (chop_start_a),
        .dac_in       (dac_a),
        .sign_bit     (sign_a),
        .dead_cycles  (dead_cycles),
        .fast_cycles  (fast_cycles),
        .slow_cycles  (slow_cycles),
        .period_cycles(period_cycles),
        .run_hold     (run_hold_s),
        .cmp_s        (cmp_a_s),
        .q1(q1_a), .q3(q3_a),
        .dac_out      (dac_a_out)
    );

    // Coil B driver
    coil_drv u_coil_b (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en_s),
        .cycle_start  (chop_start_b),
        .dac_in       (dac_b),
        .sign_bit     (sign_b),
        .dead_cycles  (dead_cycles),
        .fast_cycles  (fast_cycles),
        .slow_cycles  (slow_cycles),
        .period_cycles(period_cycles),
        .run_hold     (run_hold_s),
        .cmp_s        (cmp_b_s),
        .q1(q1_b), .q3(q3_b),
        .dac_out      (dac_b_out)
    );

endmodule
