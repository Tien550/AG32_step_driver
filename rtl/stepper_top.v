// stepper_top.v — Axis X stepper driver top level, AG32VF303 CPLD
//
// Pin mapping (from mapping.ve):
//   Inputs  (8): axis_en=PIN_1    step_pul=PIN_96   step_dir=PIN_15  run_hold=PIN_78
//                oc_cmp=PIN_17    cmp_a=PIN_95       cmp_b=PIN_93
//                microstep=PIN_2  (0=8-step, 1=16-step)
//   Outputs (10): q1_a=PIN_92  q3_a=PIN_88  dac_a[3:0]=PIN_86,84,82,80
//                 q1_b=PIN_91  q3_b=PIN_87  dac_b[3:0]=PIN_85,83,81,79
//
// Signal flow:
//   All async inputs (except step_pul) → input_sync → pre-synced signals
//   step_pul → axis_core → microstep_seq (sync + edge detect inside)
//   oc_s → oc_guard → oc_fault → AND-gates all outputs (safe state = low-side ON)
//
// IRS2111S:
//   Single IN pin per half-bridge. Internally-set dead time (480–820 ns, typ 650 ns).
//   IN=1 → high-side FET ON, low-side OFF.
//   IN=0 → high-side FET OFF, low-side ON.
//
// AHB Register Map (base = 0x60000000, word-addressed):
//   0x00: dead_cycles   [7:0]   default  79  (= 80-1; 800 ns dead time)
//   0x04: fast_cycles   [11:0]  default 499  (= 500-1; 5 µs fast decay)
//   0x08: slow_cycles   [11:0]  default 1499 (= 1500-1; 15 µs slow decay)
//   0x0C: period_cycles [11:0]  default 3332 (= 3333-1; 33.3 µs = 30 kHz chopper)
//
// Run/hold: run_hold pin — 1=run (100% LUT), 0=hold (50% LUT)
// Microstep: microstep pin — 1=16-step, 0=8-step

module ax1_top (
  // ── Axis X control inputs ──────────────────────────────────────
  input              axis_en,       // PIN_1  — axis enable (1=on)
  input              step_pul,      // PIN_96 — step pulse (rising edge = 1 microstep)
  input              step_dir,      // PIN_15 — direction (0=forward, 1=reverse)
  input              run_hold,      // PIN_78 — 1=run (100%), 0=hold (50%)
  input              microstep,     // PIN_16 — 1=16-step, 0=8-step
  // ── Overcurrent (shared) ───────────────────────────────────────
  input              oc_cmp,        // PIN_17 — active HIGH: latches system off on OC
  // ── Chopper comparators (active LOW, per coil) ─────────────────
  input              cmp_a,         // PIN_95 — coil A: 0 = current >= Vref_A
  input              cmp_b,         // PIN_93 — coil B: 0 = current >= Vref_B
  // ── Coil A gate outputs (IRS2111S IN pins) ────────────────────
  output tri0        q1_a,          // PIN_92 — coil A left  half-bridge IN
  output tri0        q3_a,          // PIN_88 — coil A right half-bridge IN
  // ── Coil A DAC (4-bit R-2R ladder → Vref_A) ──────────────────
  output tri0 [3:0]  dac_a,         // PIN_86,84,82,80 — [3]=MSB
  // ── Coil B gate outputs (IRS2111S IN pins) ────────────────────
  output tri0        q1_b,          // PIN_91 — coil B left  half-bridge IN
  output tri0        q3_b,          // PIN_87 — coil B right half-bridge IN
  // ── Coil B DAC (4-bit R-2R ladder → Vref_B) ──────────────────
  output tri0 [3:0]  dac_b,         // PIN_85,83,81,79 — [3]=MSB
  // ── System interface ──────────────────────────────────────────
  input              sys_clk,
  input              bus_clk,
  input              rst_n,
  input              stop,
  // ── AHB master interface ──────────────────────────────────────
  input       [1:0]  mem_ahb_htrans,
  input              mem_ahb_hready,
  input              mem_ahb_hwrite,
  input       [31:0] mem_ahb_haddr,
  input       [2:0]  mem_ahb_hsize,
  input       [2:0]  mem_ahb_hburst,
  input       [31:0] mem_ahb_hwdata,
  output tri1        mem_ahb_hreadyout,
  output tri0        mem_ahb_hresp,
  output tri0 [31:0] mem_ahb_hrdata,
  // ── AHB slave interface (unused) ─────────────────────────────
  output tri0        slave_ahb_hsel,
  output tri1        slave_ahb_hready,
  input              slave_ahb_hreadyout,
  output tri0 [1:0]  slave_ahb_htrans,
  output tri0 [2:0]  slave_ahb_hsize,
  output tri0 [2:0]  slave_ahb_hburst,
  output tri0        slave_ahb_hwrite,
  output tri0 [31:0] slave_ahb_haddr,
  output tri0 [31:0] slave_ahb_hwdata,
  input              slave_ahb_hresp,
  input       [31:0] slave_ahb_hrdata,
  // ── DMA interface (unused) ───────────────────────────────────
  output tri0 [3:0]  ext_dma_DMACBREQ,
  output tri0 [3:0]  ext_dma_DMACLBREQ,
  output tri0 [3:0]  ext_dma_DMACSREQ,
  output tri0 [3:0]  ext_dma_DMACLSREQ,
  input       [3:0]  ext_dma_DMACCLR,
  input       [3:0]  ext_dma_DMACTC,
  // ── Interrupt output (unused) ────────────────────────────────
  output tri0 [3:0]  local_int
);

// ============================================================
//  AHB register file (inline, shared by both coils)
// ============================================================
reg [7:0]  dead_cycles;
reg [11:0] fast_cycles, slow_cycles, period_cycles;

reg        ahb_wr;
reg [2:0]  ahb_addr;
wire       ahb_sel = mem_ahb_htrans[1] & mem_ahb_hready;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        ahb_wr   <= 1'b0;
        ahb_addr <= 3'd0;
    end else begin
        ahb_wr   <= ahb_sel & mem_ahb_hwrite;
        ahb_addr <= mem_ahb_haddr[4:2];
    end
end

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        dead_cycles   <= 8'd79;
        fast_cycles   <= 12'd499;
        slow_cycles   <= 12'd1499;
        period_cycles <= 12'd3332;
    end else if (ahb_wr) begin
        case (ahb_addr)
            3'd0: dead_cycles   <= mem_ahb_hwdata[7:0];
            3'd1: fast_cycles   <= mem_ahb_hwdata[11:0];
            3'd2: slow_cycles   <= mem_ahb_hwdata[11:0];
            3'd3: period_cycles <= mem_ahb_hwdata[11:0];
            default: ;
        endcase
    end
end

reg [11:0] ahb_hrdata_r;
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) ahb_hrdata_r <= 12'h0;
    else if (ahb_sel & !mem_ahb_hwrite) begin
        case (mem_ahb_haddr[4:2])
            3'd0: ahb_hrdata_r <= {4'h0, dead_cycles};
            3'd1: ahb_hrdata_r <= fast_cycles;
            3'd2: ahb_hrdata_r <= slow_cycles;
            3'd3: ahb_hrdata_r <= period_cycles;
            default: ahb_hrdata_r <= 12'h0;
        endcase
    end
end

assign mem_ahb_hreadyout = 1'b1;
assign mem_ahb_hrdata    = {20'h0, ahb_hrdata_r};
assign mem_ahb_hresp     = 1'b0;
assign slave_ahb_hready  = 1'b1;

// ============================================================
//  Input synchronizer — all async inputs except step_pul
// ============================================================
wire en_s, dir_s, run_hold_s, microstep_s;
wire cmp_a_s, cmp_b_s, oc_s;

input_sync u_input_sync (
    .clk        (sys_clk),
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

// ============================================================
//  OC protection latch
// ============================================================
wire oc_fault;
oc_guard u_oc_guard (
    .clk     (sys_clk),
    .rst_n   (rst_n),
    .oc_s    (oc_s),
    .oc_fault(oc_fault)
);
wire oc_ok = ~oc_fault;

// ============================================================
//  Axis X — 2-coil stepper core
// ============================================================
wire q1_a_w, q3_a_w;
wire q1_b_w, q3_b_w;
wire [3:0] dac_a_w, dac_b_w;

axis_core u_core (
    .clk          (sys_clk),
    .rst_n        (rst_n),
    .step_pul     (step_pul),
    .en_s         (en_s),
    .dir_s        (dir_s),
    .run_hold_s   (run_hold_s),
    .microstep_s  (microstep_s),
    .cmp_a_s      (cmp_a_s),
    .cmp_b_s      (cmp_b_s),
    .dead_cycles  (dead_cycles),
    .fast_cycles  (fast_cycles),
    .slow_cycles  (slow_cycles),
    .period_cycles(period_cycles),
    .q1_a(q1_a_w), .q3_a(q3_a_w), .dac_a_out(dac_a_w),
    .q1_b(q1_b_w), .q3_b(q3_b_w), .dac_b_out(dac_b_w)
);

// OC gate: oc_fault forces all IN pins LOW → both IRS2111S drive low-sides (safe)
assign q1_a = q1_a_w & oc_ok;
assign q3_a = q3_a_w & oc_ok;
assign q1_b = q1_b_w & oc_ok;
assign q3_b = q3_b_w & oc_ok;
assign dac_a = dac_a_w;
assign dac_b = dac_b_w;

// ── Unused interface tie-offs ─────────────────────────────
assign slave_ahb_hsel    = 1'b0;
assign slave_ahb_htrans  = 2'b00;
assign slave_ahb_hsize   = 3'b000;
assign slave_ahb_hburst  = 3'b000;
assign slave_ahb_hwrite  = 1'b0;
assign slave_ahb_haddr   = 32'h0;
assign slave_ahb_hwdata  = 32'h0;
assign ext_dma_DMACBREQ  = 4'h0;
assign ext_dma_DMACLBREQ = 4'h0;
assign ext_dma_DMACSREQ  = 4'h0;
assign ext_dma_DMACLSREQ = 4'h0;
assign local_int         = 4'h0;

endmodule
