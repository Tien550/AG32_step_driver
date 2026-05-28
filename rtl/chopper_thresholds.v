// chopper_thresholds.v - Combinational timing threshold calculator for PWM chopper FSM
//
// All threshold values (dead_cycles, fast_cycles, slow_cycles, period_cycles) are
// stored pre-decremented in AHB registers — no subtraction needed here.
// drive_max = period - DT_ON - DT_OFF - FAST - SLOW - transitions(6), min 1.
// cur_fast_th: fault (had_drive=0, cmp fired cycle 0) → 0; normal → fast_th.
// Zero-crossing handled by LUT (dac_min=2, never 0) — no zc_mode needed.

module chop_thresh (
    input  wire [7:0]  dead_cycles,   // AHB: desired_dead_cycles - 1
    input  wire [11:0] fast_cycles,   // AHB: desired_fast_cycles - 1
    input  wire [11:0] slow_cycles,   // AHB: desired_slow_cycles - 1
    input  wire [11:0] period_cycles, // AHB: desired_period_cycles - 1
    input  wire        had_drive,     // 0 = cmp fired on cycle 0 (fault → fast=0)
    output wire [11:0] dead_th,
    output wire [11:0] slow_th,
    output wire [11:0] drive_max,
    output wire [11:0] cur_fast_th
);

    assign dead_th = {4'h0, dead_cycles};
    wire [11:0] fast_th = fast_cycles;
    assign slow_th = slow_cycles;

    assign cur_fast_th = had_drive ? fast_th : 12'd0;

    // Each state takes (threshold+1) clocks; 5 states → +5 total.
    wire [13:0] overhead   = {2'h0, dead_th} + {2'h0, dead_th}
                           + {2'h0, fast_th}
                           + {2'h0, slow_th} + 14'd5;
    wire [13:0] period_ext = {2'h0, period_cycles};
    assign drive_max = (period_ext > overhead) ? period_ext[11:0] - overhead[11:0] : 12'd1;

endmodule
