// pwm_b_fsm.v - H-bridge chopper FSM for IRS2111S gate driver (per-coil)
//
// Sequence per chopper period:
//   S_DT_ON → S_DRIVE → S_DT_OFF → S_FAST → S_SLOW → S_OFF
//
// Zero-crossing is handled in the LUT (dac_min=2, never 0) so no special
// zero-crossing FSM path is needed.
//
// q1 = IN_L : left  IRS2111S IN pin (1=Q14 high-side, 0=Q16 low-side)
// q3 = IN_R : right IRS2111S IN pin (1=Q13 high-side, 0=Q15 low-side)
//
// IRS2111S has internally-set dead time (480–820 ns, typ 650 ns). There is
// no external DT/SD pin. Software dead time via S_DT_ON/S_DT_OFF adds margin.
// When q1=0 and q3=0, both IRS2111S drive their low-sides (Q16+Q15).
//
// Gate logic per state:
//   S_DT_ON:  q1=0, q3=0 — both low-sides on (dead-time before drive)
//   S_DRIVE:  sign=0 → q1=1,q3=0 (Q14+Q15, A→B current)
//             sign=1 → q1=0,q3=1 (Q16+Q13, B→A current)
//   S_DT_OFF: q1=0, q3=0 — both low-sides on (dead-time before freewheeling)
//   S_FAST:   decay_sign=0 → q1=0,q3=1 (reverse: Q16+Q13, actively reduces A→B current)
//             decay_sign=1 → q1=1,q3=0 (reverse: Q14+Q15, actively reduces B→A current)
//   S_SLOW:   q1=0, q3=0 — both low-sides on (slow freewheeling decay)
//   S_OFF:    q1=0, q3=0 — idle, waiting for cycle_start
//
// decay_sign vs sign_latch:
//   sign_latch  — tracks current LUT sign_bit (may flip at zero crossing before
//                 residual current decays, so using it for S_FAST would apply
//                 voltage in the WRONG direction).
//   decay_sign  — latched at S_DT_ON entry (start of each drive cycle);
//                 always matches the direction of current in the coil after that drive.
//                 Used for S_FAST to guarantee reverse-voltage application.

module hbridge_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        cycle_start,
    input  wire [7:0]  dead_cycles,
    input  wire [11:0] fast_cycles, slow_cycles,
    input  wire [11:0] period_cycles,
    input  wire        sign_bit,
    input  wire        oc_detect,
    output reg         q1,           // IN for left  IRS2111S
    output reg         q3            // IN for right IRS2111S
);

    localparam S_DT_ON  = 3'd0;
    localparam S_DRIVE  = 3'd1;
    localparam S_DT_OFF = 3'd2;
    localparam S_FAST   = 3'd3;
    localparam S_SLOW   = 3'd4;
    localparam S_OFF    = 3'd5;

    reg [2:0]  state;
    reg [11:0] timer;
    reg        had_drive;    // 1 = S_DRIVE ran ≥1 cycle; 0 = cmp fired on cycle 0 (fault)
    reg        sign_latch;   // tracks current LUT sign (updated continuously in S_OFF)
    reg        decay_sign;   // sign of last drive; used for S_FAST direction

    wire [11:0] dead_th, slow_th, drive_max_w, cur_fast_th;

    chop_thresh u_thresh (
        .dead_cycles  (dead_cycles),
        .fast_cycles  (fast_cycles),
        .slow_cycles  (slow_cycles),
        .period_cycles(period_cycles),
        .had_drive    (had_drive),
        .dead_th      (dead_th),
        .slow_th      (slow_th),
        .drive_max    (drive_max_w),
        .cur_fast_th  (cur_fast_th)
    );

    // Register drive_max to cut the long fast_cycles→overhead_adder→drive_max→had_drive path.
    // Timing parameters change only via AHB (infrequent), so 1-cycle latency has no effect.
    reg [11:0] drive_max;
    always @(posedge clk) drive_max <= drive_max_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_OFF;
            timer      <= 12'd0;
            had_drive  <= 1'b0;
            sign_latch <= 1'b0;
            decay_sign <= 1'b0;
            q1         <= 1'b0;
            q3         <= 1'b0;
        end else if (!en) begin
            state     <= S_OFF;
            timer     <= 12'd0;
            had_drive <= 1'b0;
            q1        <= 1'b0;
            q3        <= 1'b0;
        end else begin
            case (state)
                S_DT_ON: begin
                    q1 <= 1'b0; q3 <= 1'b0;
                    decay_sign <= sign_latch;  // capture drive direction for S_FAST
                    if (timer >= dead_th) begin
                        state <= S_DRIVE;
                        timer <= 12'd0;
                    end else
                        timer <= timer + 12'd1;
                end

                S_DRIVE: begin
                    if (!sign_latch) begin q1 <= 1'b1; q3 <= 1'b0; end
                    else             begin q1 <= 1'b0; q3 <= 1'b1; end
                    if (oc_detect || (timer >= drive_max)) begin
                        had_drive <= (timer != 12'd0);  // 0→cmp fault, >0→normal
                        state     <= S_DT_OFF;
                        timer     <= 12'd0;
                    end else
                        timer <= timer + 12'd1;
                end

                S_DT_OFF: begin
                    q1 <= 1'b0; q3 <= 1'b0;
                    if (timer >= dead_th) begin
                        state <= S_FAST;
                        timer <= 12'd0;
                    end else
                        timer <= timer + 12'd1;
                end

                S_FAST: begin
                    // decay_sign ensures reverse voltage always opposes actual coil current
                    if (!decay_sign) begin q1 <= 1'b0; q3 <= 1'b1; end
                    else             begin q1 <= 1'b1; q3 <= 1'b0; end
                    if (timer >= cur_fast_th) begin
                        state <= S_SLOW;
                        timer <= 12'd0;
                    end else
                        timer <= timer + 12'd1;
                end

                S_SLOW: begin
                    q1 <= 1'b0; q3 <= 1'b0;
                    if (timer >= slow_th) begin
                        state <= S_OFF;
                        timer <= 12'd0;
                    end else
                        timer <= timer + 12'd1;
                end

                S_OFF: begin
                    q1         <= 1'b0; q3 <= 1'b0;
                    sign_latch <= sign_bit;  // zero-latency capture for next drive
                    if (cycle_start)  begin
                        state <= S_DT_ON;
                        timer <= 12'd0;
                    end
                end

                default: begin
                    state <= S_OFF;
                    q1    <= 1'b0;
                    q3    <= 1'b0;
                end
            endcase
        end
    end

endmodule
