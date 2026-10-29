`timescale 1ns/1ps

// stepper_top_sim.v - Simulation-only top wrapper for axis X stepper driver (2-coil)
//
// Bypasses AHB — timing parameters are passed directly as module parameters.
// Mirrors the structure of stepper_top.v: input_sync + oc_guard + axis_core.
//
// Signal naming:
//   cmp_a    — coil A chopper comparator, active LOW (0 = current >= Vref_A)
//   cmp_b    — coil B chopper comparator, active LOW (0 = current >= Vref_B)
//   oc_cmp   — overcurrent comparator, active HIGH (level triggers oc_fault)

module ax1_sim #(
    parameter DEAD_CYCLES   = 79,
    parameter FAST_CYCLES   = 499,
    parameter SLOW_CYCLES   = 1499,
    parameter PERIOD_CYCLES = 3332
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        step_pul,
    input  wire        step_dir,
    input  wire        axis_en,
    input  wire        run_hold,
    input  wire        microstep,    // 1=16-step, 0=8-step

    // Chopper comparators (active LOW, per coil)
    input  wire        cmp_a,        // coil A: 0 = current >= Vref_A
    input  wire        cmp_b,        // coil B: 0 = current >= Vref_B

    // Overcurrent comparator (active HIGH, shared)
    input  wire        oc_cmp,       // HIGH = overcurrent; level latches oc_fault

    // Coil A gate outputs
    output wire        q1_a,         // left  IRS2111S IN — coil A
    output wire        q3_a,         // right IRS2111S IN — coil A
    output wire [3:0]  dac_a,        // 4-bit R-2R DAC Vref — coil A

    // Coil B gate outputs
    output wire        q1_b,         // left  IRS2111S IN — coil B
    output wire        q3_b,         // right IRS2111S IN — coil B
    output wire [3:0]  dac_b         // 4-bit R-2R DAC Vref — coil B
);

    // Synced signals from input_sync
    wire en_s, dir_s, run_hold_s, microstep_s;
    wire cmp_a_s, cmp_b_s, oc_s;

    input_sync u_input_sync (
        .clk        (clk),
        .rst_n      (rst_n),
        .axis_en    (axis_en),
        .step_dir   (step_dir),
        .run_hold   (run_hold),
        .microstep  (microstep),
        .cmp_a      (cmp_a),
        .cmp_b      (cmp_b),
        .oc_cmp     (oc_cmp),
        .en_s       (en_s),
        .dir_s      (dir_s),
        .run_hold_s (run_hold_s),
        .microstep_s(microstep_s),
        .cmp_a_s    (cmp_a_s),
        .cmp_b_s    (cmp_b_s),
        .oc_s       (oc_s)
    );

    // OC protection latch
    wire oc_fault;
    oc_guard u_oc_guard (
        .clk     (clk),
        .rst_n   (rst_n),
        .oc_s    (oc_s),
        .oc_fault(oc_fault)
    );
    wire oc_ok = ~oc_fault;

    // 2-coil axis core
    wire q1_a_c, q3_a_c;
    wire q1_b_c, q3_b_c;
    wire [3:0] dac_a_c, dac_b_c;

    axis_core u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .step_pul     (step_pul),
        .en_s         (en_s),
        .dir_s        (dir_s),
        .run_hold_s   (run_hold_s),
        .microstep_s  (microstep_s),
        .cmp_a_s      (cmp_a_s),
        .cmp_b_s      (cmp_b_s),
        .dead_cycles  (DEAD_CYCLES[7:0]),
        .fast_cycles  (FAST_CYCLES[11:0]),
        .slow_cycles  (SLOW_CYCLES[11:0]),
        .period_cycles(PERIOD_CYCLES[11:0]),
        .q1_a(q1_a_c), .q3_a(q3_a_c), .dac_a_out(dac_a_c),
        .q1_b(q1_b_c), .q3_b(q3_b_c), .dac_b_out(dac_b_c)
    );

    // OC gate: oc_fault forces all IN pins LOW → both IRS2111S drive low-sides
    assign q1_a = q1_a_c & oc_ok;
    assign q3_a = q3_a_c & oc_ok;
    assign q1_b = q1_b_c & oc_ok;
    assign q3_b = q3_b_c & oc_ok;
    assign dac_a = dac_a_c;
    assign dac_b = dac_b_c;

endmodule
