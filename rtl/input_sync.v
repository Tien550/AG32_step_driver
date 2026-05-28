// input_sync.v - Async input synchronizer for 1-axis stepper driver
//
// All external pin inputs except step_pul are synchronized here using
// a 2-stage flip-flop chain before entering the digital core.
//
// step_pul is excluded — it is synchronized inside microstep_seq where
// the rising-edge detect logic lives (3 FF total: sync×2 + edge-detect×1).
//
// Outputs carry the _s suffix to indicate synchronized status.

module input_sync (
    input  wire clk,
    input  wire rst_n,
    // Async pin inputs
    input  wire axis_en,     // Axis enable (active HIGH)
    input  wire step_dir,    // Step direction (0=forward, 1=reverse)
    input  wire run_hold,    // 1=Run (100%), 0=Hold (50% current)
    input  wire microstep,   // 1=16-step, 0=8-step
    input  wire cmp_a,       // Coil A chopper comparator (active LOW)
    input  wire cmp_b,       // Coil B chopper comparator (active LOW)
    input  wire oc_cmp,      // Overcurrent comparator (active HIGH)
    // Synchronized outputs
    output wire en_s,
    output wire dir_s,
    output wire run_hold_s,
    output wire microstep_s,
    output wire cmp_a_s,
    output wire cmp_b_s,
    output wire oc_s
);

    syn_in_signal #(.STAGES(2)) u_syn_en   (.clk(clk),.rst_n(rst_n),.async_in(axis_en),  .sync_out(en_s));
    syn_in_signal #(.STAGES(2)) u_syn_dir  (.clk(clk),.rst_n(rst_n),.async_in(step_dir), .sync_out(dir_s));
    syn_in_signal #(.STAGES(2)) u_syn_rh   (.clk(clk),.rst_n(rst_n),.async_in(run_hold), .sync_out(run_hold_s));
    syn_in_signal #(.STAGES(2)) u_syn_ms   (.clk(clk),.rst_n(rst_n),.async_in(microstep),.sync_out(microstep_s));
    syn_in_signal #(.STAGES(2)) u_syn_cmpa (.clk(clk),.rst_n(rst_n),.async_in(cmp_a),    .sync_out(cmp_a_s));
    syn_in_signal #(.STAGES(2)) u_syn_cmpb (.clk(clk),.rst_n(rst_n),.async_in(cmp_b),    .sync_out(cmp_b_s));
    syn_in_signal #(.STAGES(2)) u_syn_oc   (.clk(clk),.rst_n(rst_n),.async_in(oc_cmp),   .sync_out(oc_s));

endmodule
