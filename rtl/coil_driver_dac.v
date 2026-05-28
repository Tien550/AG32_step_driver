// coil_driver_dac.v - Single-coil driver: 4-bit Vref DAC + chopper gate FSM
// q1 (IN_L) and q3 (IN_R) drive IRS2111S IN pins directly.
// IRS2111S has internally-set dead time (650 ns typ). No external DT pin.
// cmp_s: active LOW — 0 = current reached Vref → end DRIVE phase.
//        Pre-synchronized by input_sync (no sync stage needed here).

module coil_drv (
    input  wire        clk, rst_n, en,
    input  wire        cycle_start,
    input  wire [3:0]  dac_in,
    input  wire        sign_bit,
    input  wire [7:0]  dead_cycles,
    input  wire [11:0] fast_cycles, slow_cycles,
    input  wire [11:0] period_cycles,
    input  wire        run_hold,
    input  wire        cmp_s,        // Pre-synced chopper comparator (active LOW)
    output wire        q1, q3,
    output wire [3:0]  dac_out
);

    wire [3:0] dac_raw;

    vref_dac u_vref_dac (
        .clk     (clk),
        .rst_n   (rst_n),
        .dac_in  (dac_in),
        .run_hold(run_hold),
        .dac_out (dac_raw)
    );

    assign dac_out = en ? dac_raw : 4'd0;

    hbridge_fsm u_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .cycle_start  (cycle_start),
        .dead_cycles  (dead_cycles),
        .fast_cycles  (fast_cycles),
        .slow_cycles  (slow_cycles),
        .period_cycles(period_cycles),
        .sign_bit     (sign_bit),
        .oc_detect    (~cmp_s),
        .q1(q1), .q3(q3)
    );

endmodule
