`timescale 1ns/1ps

// tb_stepper.v - Testbench for axis X 2-coil stepper driver
//
// DUT: ax1_sim (axis_core + input_sync + oc_guard, no AHB)
//
// Test cases:
//   TC1  — Reset: all gate outputs LOW during reset
//   TC2  — FSM full cycle: verify S_DRIVE / S_FAST / S_SLOW states (coil A)
//   TC3  — 16-step sign change: S_FAST output polarity vs sign_bit (coil A)
//   TC4  — Direction control: step_cnt increment / decrement
//   TC5  — Hold mode DAC scaling: dac_a at step=4 (sin peak)
//          Hold = 50% of LUT: hold_dac = floor(15/2) = 7
//   TC6  — Enable control: all gate outputs LOW when axis_en=0
//   TC7  — FAST/SLOW state width measurement (coil A)
//   TC8  — OC: oc_cmp latches oc_fault, persists after oc_cmp=0
//   TC9  — Pulse accepted in hold mode: step_cnt advances when run_hold=0
//   TC10 — dac_zero skips S_DT_ON/S_DRIVE: coil A at step=0
//   TC11 — Coil interleave: coil A and coil B not simultaneously in S_DRIVE
//   TC12 — Pulse accepted immediately after reset (no startup inhibit)

module tb_stepper;

    // ─────────────────────────────────────────────────────────────
    // Simulation parameters
    // ─────────────────────────────────────────────────────────────
    localparam CLK_PERIOD   = 10;    // 10 ns = 100 MHz
    localparam SIM_DEAD     = 79;    // = 80-1; 800 ns dead time
    localparam SIM_FAST     = 499;   // = 500-1; 5 µs fast decay
    localparam SIM_SLOW     = 1499;  // = 1500-1; 15 µs slow decay
    localparam SIM_PERIOD   = 3332;  // period-1; 3333 clocks = 33.3 µs = 30 kHz

    // Small settling delay after reset (2-stage input_sync + 1 register = 3 cycles)
    localparam SETTLE_CYCLES = 5;

    // ─────────────────────────────────────────────────────────────
    // Testbench signals
    // ─────────────────────────────────────────────────────────────
    reg  clk, rst_n;
    reg  step_pul, step_dir, axis_en, run_hold;
    reg  microstep;

    // Comparators
    reg  cmp_a;     // coil A chopper, active LOW
    reg  cmp_b;     // coil B chopper, active LOW
    reg  oc_cmp;    // overcurrent latch, active HIGH

    // Coil A outputs
    wire        q1_a, q3_a;
    wire [3:0]  dac_a;

    // Coil B outputs
    wire        q1_b, q3_b;
    wire [3:0]  dac_b;

    // ─────────────────────────────────────────────────────────────
    // DUT
    // ─────────────────────────────────────────────────────────────
    ax1_sim #(
        .DEAD_CYCLES  (SIM_DEAD),
        .FAST_CYCLES  (SIM_FAST),
        .SLOW_CYCLES  (SIM_SLOW),
        .PERIOD_CYCLES(SIM_PERIOD)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .step_pul (step_pul),
        .step_dir (step_dir),
        .axis_en  (axis_en),
        .run_hold (run_hold),
        .microstep(microstep),
        .cmp_a    (cmp_a),
        .cmp_b    (cmp_b),
        .oc_cmp   (oc_cmp),
        .q1_a(q1_a), .q3_a(q3_a), .dac_a(dac_a),
        .q1_b(q1_b), .q3_b(q3_b), .dac_b(dac_b)
    );

    // ─────────────────────────────────────────────────────────────
    // Clock (100 MHz)
    // ─────────────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ─────────────────────────────────────────────────────────────
    // VCD waveform dump
    // ─────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_stepper);
    end

    // ─────────────────────────────────────────────────────────────
    // Helper tasks
    // ─────────────────────────────────────────────────────────────
    task send_pulse;
        input [31:0] pw_cycles;
        begin
            step_pul = 1;
            repeat(pw_cycles) @(posedge clk);
            step_pul = 0;
            @(posedge clk);
        end
    endtask

    task wait_chopper;
        input [31:0] n;
        repeat(n * SIM_PERIOD) @(posedge clk);
    endtask

    task print_gates;
        $display("t=%0t | A: q1=%b q3=%b dac=%0d | B: q1=%b q3=%b dac=%0d",
                 $time, q1_a, q3_a, dac_a, q1_b, q3_b, dac_b);
    endtask

    // ─────────────────────────────────────────────────────────────
    // Test helper variables
    // ─────────────────────────────────────────────────────────────
    integer i, scan;
    integer err_count;
    reg     found;
    integer dac_val_run, dac_val_hold;
    integer s0, s1, s2, s3;
    integer expected_s1, expected_s2;
    integer slow_start, slow_len, slow_len_min, slow_len_max;
    integer fast_start, fast_len, fast_len_min, fast_len_max;
    integer cycle_idx;
    reg     in_slow, in_fast;
    integer cnt_ab_drive;

    // ─────────────────────────────────────────────────────────────
    // CMP model — coil A (active LOW: 0 = current reached Vref_A)
    //
    // Fires during S_DRIVE from cycle 0 (no blank window).
    // Trip time proportional to dac_a magnitude × CMP_K.
    // cmp_a stays HIGH (idle) outside S_DRIVE.
    // ─────────────────────────────────────────────────────────────
    localparam CMP_K = 1000000;

    always @(posedge clk) begin
        if (!rst_n || !axis_en) begin
            cmp_a <= 1'b1;  // idle: no trip
        end else begin
            if (dut.u_core.u_coil_a.u_fsm.state == 3'd1) begin
                if (dut.u_core.u_coil_a.u_fsm.timer >=
                    (dut.u_core.dac_a * CMP_K * 2 + 1))
                    cmp_a <= 1'b0;  // trip: current reached Vref_A (active LOW)
                else
                    cmp_a <= 1'b1;
            end else
                cmp_a <= 1'b1;
        end
    end

    // ─────────────────────────────────────────────────────────────
    // CMP model — coil B (active LOW: 0 = current reached Vref_B)
    // ─────────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n || !axis_en) begin
            cmp_b <= 1'b1;
        end else begin
            if (dut.u_core.u_coil_b.u_fsm.state == 3'd1) begin
                if (dut.u_core.u_coil_b.u_fsm.timer >=
                    (dut.u_core.dac_b * CMP_K * 2 + 1))
                    cmp_b <= 1'b0;
                else
                    cmp_b <= 1'b1;
            end else
                cmp_b <= 1'b1;
        end
    end

    // ─────────────────────────────────────────────────────────────
    // Main test sequence
    // ─────────────────────────────────────────────────────────────
    initial begin
        rst_n = 0; step_pul = 0; step_dir = 0;
        axis_en = 0; run_hold = 1; microstep = 1;
        cmp_a = 1'b1; cmp_b = 1'b1; oc_cmp = 0;
        err_count = 0;

        // ── Parameter verification ──────────────────────────────
        $display("\n=== DEBUG: Parameter Verification ===");
        $display("  TB    SIM_DEAD       = %0d", SIM_DEAD);
        $display("  TB    SIM_FAST       = %0d", SIM_FAST);
        $display("  TB    SIM_SLOW       = %0d", SIM_SLOW);
        $display("  TB    SIM_PERIOD     = %0d", SIM_PERIOD);
        $display("  DUT   DEAD_CYCLES   = %0d", dut.DEAD_CYCLES);
        $display("  DUT   FAST_CYCLES   = %0d", dut.FAST_CYCLES);
        $display("  DUT   SLOW_CYCLES   = %0d", dut.SLOW_CYCLES);
        $display("  DUT   PERIOD_CYCLES = %0d", dut.PERIOD_CYCLES);
        $display("  (blank window removed — cmp checked from cycle 0 of S_DRIVE)");

        // ─────────────────────────────────────────────────────────
        // TC1: Reset — all 4 gate outputs must be LOW
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC1: Reset Verification ===");
        repeat(5) @(posedge clk);
        if (q1_a | q3_a | q1_b | q3_b) begin
            $display("FAIL TC1: gate(s) not LOW during reset (A:%b%b B:%b%b)",
                     q1_a, q3_a, q1_b, q3_b);
            err_count = err_count + 1;
        end else
            $display("PASS TC1: all gates LOW during reset");

        @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ─────────────────────────────────────────────────────────
        // TC2: FSM full cycle — coil A at step=1 (dac_a=6, sign=0)
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC2: FSM Full Cycle — Coil A (step=1, dac=6, sign=0) ===");
        axis_en = 1; run_hold = 1;
        repeat(SETTLE_CYCLES) @(posedge clk);
        send_pulse(4);       // advance step_cnt 0 → 1
        wait_chopper(2);

        found = 0;
        for (scan = 0; scan < 3*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);
            if (q1_a & ~q3_a) found = 1;
        end
        if (found) $display("PASS TC2-DRIVE: q1_a=1, q3_a=0 detected");
        else begin  $display("FAIL TC2-DRIVE: q1_a=1, q3_a=0 NOT detected"); err_count=err_count+1; end

        found = 0;
        for (scan = 0; scan < 3*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);
            if (~q1_a & q3_a) found = 1;
        end
        if (found) $display("PASS TC2-FAST:  q1_a=0, q3_a=1 detected");
        else begin  $display("FAIL TC2-FAST:  q1_a=0, q3_a=1 NOT detected"); err_count=err_count+1; end

        found = 0;
        for (scan = 0; scan < 3*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);
            if (dut.u_core.u_coil_a.u_fsm.state == 3'd4) found = 1;
        end
        if (found) $display("PASS TC2-SLOW:  S_SLOW state detected");
        else begin  $display("FAIL TC2-SLOW:  S_SLOW NOT detected"); err_count=err_count+1; end

        // ─────────────────────────────────────────────────────────
        // TC3: 16-step sign change — coil A S_FAST output polarity
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC3: 16-Step Sign Change (step_dir=0, count up) ===");
        step_dir = 0;
        for (i = 0; i < 16; i = i+1) begin
            send_pulse(4);
            wait_chopper(1);

            found = 0;
            for (scan = 0; scan < 2*SIM_PERIOD; scan = scan+1) begin
                @(posedge clk);
                if      (i < 7)  begin if (~q1_a & q3_a) found = 1; end
                else if (i == 7) found = 1;  // step 8: dac=0, skip FAST check
                else if (i < 15) begin if (q1_a & ~q3_a) found = 1; end
                else             found = 1;  // step 0: dac=0, skip FAST check
            end

            $display("TC3 step %2d | %s | %s",
                     (i+1) % 16,
                     (i < 7)  ? "sign=0 (q1_a=0,q3_a=1)" :
                     (i == 7) ? "step8: dac=0, skip S_FAST" :
                     (i < 15) ? "sign=1 (q1_a=1,q3_a=0)" : "step0: dac=0, skip S_FAST",
                     found ? "PASS" : "FAIL");
            if (!found) err_count = err_count + 1;

            wait_chopper(1);
        end

        // ─────────────────────────────────────────────────────────
        // TC4: Direction control — step_cnt increment/decrement
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC4: Direction Control ===");

        @(posedge clk);
        s0 = dut.u_core.u_ms_seq.step_cnt;
        $display("TC4 initial step_cnt = %0d", s0);

        step_dir = 0;
        send_pulse(4);
        repeat(10) @(posedge clk);
        s1 = dut.u_core.u_ms_seq.step_cnt;
        expected_s1 = (s0 + 1) % 16;
        if (s1 == expected_s1)
            $display("PASS TC4-FWD:  step_dir=0: %0d → %0d", s0, s1);
        else begin
            $display("FAIL TC4-FWD:  step_dir=0: %0d → %0d (expected %0d)", s0, s1, expected_s1);
            err_count = err_count + 1;
        end

        step_dir = 1;
        repeat(5) @(posedge clk);
        send_pulse(4);
        repeat(10) @(posedge clk);
        s2 = dut.u_core.u_ms_seq.step_cnt;
        expected_s2 = (s1 == 0) ? 15 : s1 - 1;
        if (s2 == expected_s2)
            $display("PASS TC4-REV:  step_dir=1: %0d → %0d", s1, s2);
        else begin
            $display("FAIL TC4-REV:  step_dir=1: %0d → %0d (expected %0d)", s1, s2, expected_s2);
            err_count = err_count + 1;
        end

        repeat(5) @(posedge clk);
        send_pulse(4); repeat(10) @(posedge clk);
        send_pulse(4); repeat(10) @(posedge clk);
        s3 = dut.u_core.u_ms_seq.step_cnt;
        expected_s2 = (s2 == 0) ? 15 : s2 - 1;
        expected_s2 = (expected_s2 == 0) ? 15 : expected_s2 - 1;
        if (s3 == expected_s2)
            $display("PASS TC4-REV2: step_dir=1: %0d → %0d (2 pulses)", s2, s3);
        else begin
            $display("FAIL TC4-REV2: step_dir=1: %0d → %0d (expected %0d)", s2, s3, expected_s2);
            err_count = err_count + 1;
        end

        step_dir = 0;
        repeat(5) @(posedge clk);

        // ─────────────────────────────────────────────────────────
        // TC5: Hold mode DAC scaling — coil A at step_cnt=4 (sin peak)
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC5: Hold Mode DAC Scaling — Coil A (step=4, sin peak) ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(SETTLE_CYCLES) @(posedge clk);
        axis_en = 1; wait_chopper(1);

        step_dir = 0;
        repeat(4) begin
            send_pulse(4);
            wait_chopper(1);
        end
        $display("TC5: step_cnt=%0d (expected 4, dac_in=15 for coil A)",
                 dut.u_core.u_ms_seq.step_cnt);

        run_hold = 1;
        wait_chopper(1);
        @(posedge clk);
        dac_val_run = dac_a;
        $display("Run  (run_hold=1): dac_a=%0d (expected 15)", dac_val_run);

        run_hold = 0;
        wait_chopper(1);
        @(posedge clk);
        dac_val_hold = dac_a;
        $display("Hold (run_hold=0): dac_a=%0d (expected 7 = floor(15/2))", dac_val_hold);

        if (dac_val_hold < dac_val_run)
            $display("PASS TC5-LT:   hold_dac (%0d) < run_dac (%0d)", dac_val_hold, dac_val_run);
        else begin
            $display("FAIL TC5-LT:   hold_dac (%0d) >= run_dac (%0d)", dac_val_hold, dac_val_run);
            err_count = err_count + 1;
        end

        if (dac_val_hold == 7)
            $display("PASS TC5-VAL:  hold_dac = 7 (correct: floor(15/2) = 50%%)");
        else begin
            $display("FAIL TC5-VAL:  hold_dac = %0d (expected 7)", dac_val_hold);
            err_count = err_count + 1;
        end

        // ─────────────────────────────────────────────────────────
        // TC6: Enable control — all 4 gate outputs must go LOW
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC6: Enable Control ===");
        run_hold = 1;
        wait_chopper(1);
        axis_en = 0;
        repeat(5) @(posedge clk);
        if (q1_a | q3_a | q1_b | q3_b) begin
            $display("FAIL TC6: gate(s) HIGH when axis_en=0 (A:%b%b B:%b%b)",
                     q1_a, q3_a, q1_b, q3_b);
            err_count = err_count + 1;
        end else
            $display("PASS TC6: all gates LOW when axis_en=0");

        // ─────────────────────────────────────────────────────────
        // TC7: FAST/SLOW state width — measured on coil A FSM
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC7: FAST/SLOW Width Measurement (coil A) ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(SETTLE_CYCLES) @(posedge clk);
        axis_en = 1; run_hold = 1;

        send_pulse(4);
        wait_chopper(2);

        while (dut.u_core.u_coil_a.u_fsm.state == 3'd4) @(posedge clk);
        while (dut.u_core.u_coil_a.u_fsm.state == 3'd3) @(posedge clk);

        slow_len_min = 32'h7FFFFFFF; slow_len_max = 0;
        fast_len_min = 32'h7FFFFFFF; fast_len_max = 0;
        in_slow = 0; in_fast = 0;
        slow_start = 0; fast_start = 0;
        cycle_idx = 0;

        for (scan = 0; scan < 5*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);

            if (dut.u_core.u_coil_a.u_fsm.state == 3'd4) begin
                if (!in_slow) begin slow_start = scan; in_slow = 1; end
            end else if (in_slow) begin
                slow_len = scan - slow_start;
                if (slow_len < slow_len_min) slow_len_min = slow_len;
                if (slow_len > slow_len_max) slow_len_max = slow_len;
                in_slow = 0; cycle_idx = cycle_idx + 1;
            end

            if (dut.u_core.u_coil_a.u_fsm.state == 3'd3) begin
                if (!in_fast) begin fast_start = scan; in_fast = 1; end
            end else if (in_fast) begin
                fast_len = scan - fast_start;
                if (fast_len < fast_len_min) fast_len_min = fast_len;
                if (fast_len > fast_len_max) fast_len_max = fast_len;
                in_fast = 0;
            end
        end

        $display("TC7: FAST width min=%0d max=%0d clk (expected %0d ±2)",
                 fast_len_min, fast_len_max, SIM_FAST);
        $display("TC7: SLOW width min=%0d max=%0d clk (expected %0d ±2)",
                 slow_len_min, slow_len_max, SIM_SLOW);

        if ((fast_len_min >= SIM_FAST - 2) && (fast_len_max <= SIM_FAST + 2))
            $display("PASS TC7-FAST: width matches");
        else begin
            $display("FAIL TC7-FAST: width deviation");
            err_count = err_count + 1;
        end

        if ((slow_len_min >= SIM_SLOW - 2) && (slow_len_max <= SIM_SLOW + 2))
            $display("PASS TC7-SLOW: width matches");
        else begin
            $display("FAIL TC7-SLOW: width deviation");
            err_count = err_count + 1;
        end

        // ─────────────────────────────────────────────────────────
        // TC8: OC latch protection
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC8: OC Latch Protection (all 4 gates) ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(3) @(posedge clk);
        axis_en = 1; run_hold = 1; oc_cmp = 0;

        repeat(SETTLE_CYCLES) @(posedge clk);
        wait_chopper(1);

        $display("TC8-A: oc_cmp=1 → oc_fault latches → all gates LOW...");
        oc_cmp = 1;
        repeat(5) @(posedge clk);
        if (q1_a | q3_a | q1_b | q3_b) begin
            $display("FAIL TC8-A: gate(s) still HIGH (A:%b%b B:%b%b)",
                     q1_a, q3_a, q1_b, q3_b);
            err_count = err_count + 1;
        end else
            $display("PASS TC8-A: all gates LOW after OC event");
        print_gates;

        $display("TC8-B: oc_cmp=0 → oc_fault must PERSIST (D-FF latch)...");
        oc_cmp = 0;
        wait_chopper(2);
        found = 0;
        for (scan = 0; scan < 2*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);
            if (q1_a | q3_a | q1_b | q3_b) found = 1;
        end
        if (!found)
            $display("PASS TC8-B: oc_fault persists after oc_cmp=0 — latch holding");
        else begin
            $display("FAIL TC8-B: gates resumed after oc_cmp=0 — latch not holding");
            err_count = err_count + 1;
        end
        print_gates;

        oc_cmp = 0;
        rst_n = 0;

        // ─────────────────────────────────────────────────────────
        // TC9: Pulse accepted in hold mode
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC9: Pulse Accepted in Hold Mode ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(SETTLE_CYCLES) @(posedge clk);
        axis_en = 1; run_hold = 1; step_dir = 0;
        wait_chopper(1);

        @(posedge clk);
        s0 = dut.u_core.u_ms_seq.step_cnt;
        $display("TC9: step_cnt before hold=%0d", s0);

        run_hold = 0;
        repeat(10) @(posedge clk);

        send_pulse(4);
        repeat(10) @(posedge clk);

        s1 = dut.u_core.u_ms_seq.step_cnt;
        expected_s1 = (s0 + 1) % 16;
        if (s1 == expected_s1)
            $display("PASS TC9: step_cnt advanced in hold: %0d → %0d", s0, s1);
        else begin
            $display("FAIL TC9: step_cnt NOT advanced: %0d → %0d (expected %0d)",
                     s0, s1, expected_s1);
            err_count = err_count + 1;
        end

        run_hold = 1;

        // ─────────────────────────────────────────────────────────
        // TC10: zero-crossing fast+slow decay at step=0 (dac=0)
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC10: Zero-Crossing Fast+Slow Decay (Coil A at step=0) ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(5) @(posedge clk);
        axis_en = 1; run_hold = 1;
        wait_chopper(1);

        $display("TC10: step_cnt=%0d, dac_a=%0d (expected step=0, dac=0)",
                 dut.u_core.u_ms_seq.step_cnt, dut.u_core.dac_a);

        begin : TC10_CHECK
            integer saw_dt_on, saw_drive, saw_fast, saw_slow;
            saw_dt_on = 0; saw_drive = 0; saw_fast = 0; saw_slow = 0;
            for (scan = 0; scan < 5*SIM_PERIOD; scan = scan+1) begin
                @(posedge clk);
                if (dut.u_core.u_coil_a.u_fsm.state == 3'd0) saw_dt_on = 1;
                if (dut.u_core.u_coil_a.u_fsm.state == 3'd1) saw_drive = 1;
                if (dut.u_core.u_coil_a.u_fsm.state == 3'd3) saw_fast  = 1;
                if (dut.u_core.u_coil_a.u_fsm.state == 3'd4) saw_slow  = 1;
            end
            if (!saw_dt_on && !saw_drive)
                $display("PASS TC10-SKIP:  S_DT_ON and S_DRIVE not entered at dac=0");
            else begin
                $display("FAIL TC10-SKIP:  S_DT_ON=%0d S_DRIVE=%0d entered at dac=0",
                         saw_dt_on, saw_drive);
                err_count = err_count + 1;
            end
            if (saw_fast)
                $display("PASS TC10-FAST:  S_FAST entered (active quench with decay_sign)");
            else begin
                $display("FAIL TC10-FAST:  S_FAST not entered — no active quench");
                err_count = err_count + 1;
            end
            if (saw_slow)
                $display("PASS TC10-SLOW:  S_SLOW entered (final freewheeling decay)");
            else begin
                $display("FAIL TC10-SLOW:  S_SLOW not entered — no decay path");
                err_count = err_count + 1;
            end
        end

        // ─────────────────────────────────────────────────────────
        // TC11: Coil A and B not simultaneously in S_DRIVE
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC11: Coil Interleave — No Simultaneous S_DRIVE ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(SETTLE_CYCLES) @(posedge clk);
        axis_en = 1; run_hold = 1; step_dir = 0;

        send_pulse(4);
        wait_chopper(2);

        cnt_ab_drive = 0;
        for (scan = 0; scan < 10*SIM_PERIOD; scan = scan+1) begin
            @(posedge clk);
            if ((dut.u_core.u_coil_a.u_fsm.state == 3'd1) &&
                (dut.u_core.u_coil_b.u_fsm.state == 3'd1))
                cnt_ab_drive = cnt_ab_drive + 1;
        end

        $display("TC11: simultaneous S_DRIVE cycles = %0d out of %0d measured",
                 cnt_ab_drive, 10*SIM_PERIOD);
        if (cnt_ab_drive == 0)
            $display("PASS TC11: coils A and B never both in S_DRIVE simultaneously");
        else begin
            $display("FAIL TC11: coils in S_DRIVE together %0d time(s)", cnt_ab_drive);
            err_count = err_count + 1;
        end

        // ─────────────────────────────────────────────────────────
        // TC12: Pulse accepted immediately after reset
        // ─────────────────────────────────────────────────────────
        $display("\n=== TC12: Pulse Accepted Immediately After Reset ===");

        rst_n = 0; repeat(5) @(posedge clk);
        rst_n = 1; repeat(SETTLE_CYCLES) @(posedge clk);
        axis_en = 1; run_hold = 1; step_dir = 0;

        s1 = dut.u_core.u_ms_seq.step_cnt;
        send_pulse(4);
        repeat(10) @(posedge clk);

        s2 = dut.u_core.u_ms_seq.step_cnt;
        if (s2 == (s1 + 1) % 16)
            $display("PASS TC12: pulse accepted immediately after reset (step_cnt %0d → %0d)", s1, s2);
        else begin
            $display("FAIL TC12: step_cnt %0d → %0d (expected %0d)", s1, s2, (s1+1)%16);
            err_count = err_count + 1;
        end

        // ─────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────
        $display("\n==========================================");
        if (err_count == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: FAILED — %0d error(s)", err_count);
        $display("==========================================\n");
        $finish;
    end

    // ─────────────────────────────────────────────────────────────
    // Watchdog
    // ─────────────────────────────────────────────────────────────
    initial begin
        #200000000;
        $display("TIMEOUT: simulation exceeded 200 ms");
        $finish;
    end

endmodule
