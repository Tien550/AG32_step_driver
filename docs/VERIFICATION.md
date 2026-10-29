# Simulation and Testbench Verification Report

This document details the testbench architecture, simulation test cases, and functional verification results for the 1-axis stepper driver core.

---

## 1. Testbench Overview (`rtl/tb_stepper.v`)

The testbench tests the complete mixed-signal digital core (`ax1_sim`) at a **100 MHz clock rate** (10 ns clock period):
- **Simulation Tool:** Vivado XSim / ModelSim / Icarus Verilog.
- **Clock Period:** 10.00 ns (`sys_clk`).
- **Timing Benchmarks:**
  - `SIM_DEAD`: 79 cycles = 800 ns
  - `SIM_FAST`: 499 cycles = 5.0 $\mu\text{s}$
  - `SIM_SLOW`: 1499 cycles = 15.0 $\mu\text{s}$
  - `SIM_PERIOD`: 3332 cycles = 33.33 $\mu\text{s}$ (30 kHz chopper)

---

## 2. Test Suite Summary (12 Test Cases)

| Test Case | Target Feature | Stimulus & Assertion | Status |
| :---: | :--- | :--- | :---: |
| **TC1** | **Reset Behavior** | Assert `rst_n = 0`. Assert all gate outputs `q1_a, q3_a, q1_b, q3_b` are driven LOW (`0`). | **PASS** |
| **TC2** | **FSM Full Cycle** | Single chopper period at step 1 (`dac = 6, sign = 0`). Assert sequence `S_DRIVE` $\rightarrow$ `S_FAST` $\rightarrow$ `S_SLOW` with matching gate polarities. | **PASS** |
| **TC3** | **16-Step Sign Change** | Step through all 16 microstep states (0 to 15). Assert correct `sign_bit` polarity and reverse voltage direction during `S_FAST`. | **PASS** |
| **TC4** | **Direction Control** | Step forward (`step_dir = 0`: $1 \rightarrow 2$), step reverse (`step_dir = 1`: $2 \rightarrow 1$), wrap reverse ($1 \rightarrow 15$). | **PASS** |
| **TC5** | **Hold Mode Scaling** | Measure `dac_a` at sine peak (`step_cnt = 4`): Run mode (`run_hold = 1`) = 15; Hold mode (`run_hold = 0`) = 7 ($\lfloor 15 / 2 \rfloor$). | **PASS** |
| **TC6** | **Enable Control** | Deassert `axis_en = 0`. Assert all gate outputs immediately forced LOW and FSM returns to `S_OFF`. | **PASS** |
| **TC7** | **Pulse Width Measurement** | Measure exact cycle duration of `S_FAST` (500 clocks) and `S_SLOW` (1500 clocks). Error margin $\le \pm 2$ clocks. | **PASS** |
| **TC8** | **Overcurrent Protection** | Inject `oc_cmp = 1`. Assert all gate outputs clamped LOW within blanking window. Deassert `oc_cmp = 0` and assert fault remains latched. | **PASS** |
| **TC9** | **Step Pulse in Hold Mode** | Inject step pulse while in hold mode (`run_hold = 0`). Assert `step_cnt` advances accurately ($0 \rightarrow 1$). | **PASS** |
| **TC10**| **Zero-Crossing Handling** | Evaluate zero-crossing microstep. Assert safe transition without reverse overdrive. | **PASS** |
| **TC11**| **Coil Phase Interleaving** | Verify phase offset between Coil A and Coil B chopper cycles to minimize peak power rail current draw. | **PASS** |
| **TC12**| **Startup Responsiveness** | Inject step pulse immediately following reset release. Assert step registered with zero startup delay or pulse dropping. | **PASS** |

---

## 3. Running Simulation Locally

### Using Vivado XSim:
```bash
cd rtl/project_2
vivado -mode batch -source ../../scripts/run_sim.tcl
```

### Using Icarus Verilog:
```bash
iverilog -o sim_stepper.vvp -g2012 \
    rtl/syn_in_signal.v \
    rtl/input_sync.v \
    rtl/blanking_filter.v \
    rtl/oc_latch.v \
    rtl/chopper_timer.v \
    rtl/sine_lut.v \
    rtl/step_sequencer.v \
    rtl/chopper_thresholds.v \
    rtl/pwm_b_fsm.v \
    rtl/dac4_vref.v \
    rtl/coil_driver_dac.v \
    rtl/stepper_axis.v \
    rtl/tb_stepper.v

vvp sim_stepper.vvp
```
