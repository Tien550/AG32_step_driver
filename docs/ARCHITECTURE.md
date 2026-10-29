# System Architecture — AG32 1-Axis Stepper Driver

This document details the system and hardware logic architecture of the 1-axis bipolar stepper motor driver implemented on the **AGM AG32VF303** SoC.

---

## 1. System Overview

The AG32VF303 integrates:
1. **RISC-V RV32IMAFC Microcontroller Core:** Running at 100 MHz, executing firmware to initialize peripherals, configure driver parameters over the internal AHB-Lite bus, and manage system monitoring.
2. **Embedded FPGA/CPLD Fabric:** ~2,000 equivalent LUTs directly connected to the internal 32-bit AHB-Lite bus, providing cycle-accurate hardware timing, mixed-decay chopper FSMs, microstepping lookup tables, and ultra-fast overcurrent shutdown.

```
+-------------------------------------------------------------------------+
|                           AGM AG32VF303 SoC                             |
|                                                                         |
|  +--------------------+                    +-------------------------+  |
|  | RISC-V 32-bit MCU  |    Internal AHB    |    Embedded CPLD/FPGA   |  |
|  |    (100 MHz)       |===================>|       Logic Core        |  |
|  |  main.c / SDK      |   Base: 0x60000000 |   (Mixed Decay Chopper) |  |
|  +--------------------+                    +-------------------------+  |
|                                                |         |              |
+------------------------------------------------|---------|--------------+
                                                 |         |
                                    Gate Signals |         | 4-bit R-2R
                                   (q1_a, q3_a,  |         | DAC References
                                    q1_b, q3_b)  |         | (Vref_A, Vref_B)
                                                 v         v
                                         +---------------+---------------+
                                         | 4x IRS2111S   | 2x Comparators|
                                         | Half-Bridge   | Peak Current  |
                                         | Drivers + FETs| Sensing Shunts|
                                         +---------------+---------------+
                                                 |
                                                 v
                                        2-Phase Bipolar
                                         Stepper Motor
```

---

## 2. Top-Level RTL Hierarchy

The Verilog RTL hierarchy is organized as follows:

```
ax1_top (stepper_top.v)
├── AHB Register File (mem_ahb_*)
├── input_sync (input_sync.v)
│   └── 7x syn_in_signal (2-stage synchronizers)
├── oc_guard (oc_latch.v)
│   └── blanking_filter (80 ns digital glitch blanking)
└── axis_core (stepper_axis.v)
    ├── chop_timer (chopper_timer.v)
    ├── microstep_seq (step_sequencer.v)
    │   ├── syn_in_signal (2-stage synchronizer for step_pul)
    │   ├── microstep_lut (u_lut_a, OFFSET=0, Coil A sine)
    │   └── microstep_lut (u_lut_b, OFFSET=4, Coil B cosine)
    ├── coil_drv u_coil_a (coil_driver_dac.v)
    │   ├── vref_dac (dac4_vref.v)
    │   └── hbridge_fsm (pwm_b_fsm.v)
    │       └── chop_thresh (chopper_thresholds.v)
    └── coil_drv u_coil_b (coil_driver_dac.v)
        ├── vref_dac (dac4_vref.v)
        └── hbridge_fsm (pwm_b_fsm.v)
            └── chop_thresh (chopper_thresholds.v)
```

---

## 3. Module Details & Signal Flow

### 3.1 Top-Level (`ax1_top` in `rtl/stepper_top.v`)
- **AHB Register File:** Decodes 32-bit AHB-Lite transactions targeted at `0x60000000` to configure chopper parameters:
  - `dead_cycles` [7:0]
  - `fast_cycles` [11:0]
  - `slow_cycles` [11:0]
  - `period_cycles` [11:0]
- **Output Gate Clamping:** Gate drive outputs `q1_a, q3_a, q1_b, q3_b` are AND-gated with `oc_ok = ~oc_fault`. If overcurrent trips, all gate inputs are forced to `0`.

### 3.2 Input Synchronizers (`input_sync.v` & `syn_in_signal.v`)
- All asynchronous inputs from external pins (`axis_en`, `step_dir`, `run_hold`, `microstep`, `cmp_a`, `cmp_b`, `oc_cmp`) pass through dedicated 2-stage D-flip-flop synchronizers to eliminate metastability before reaching control logic.
- `step_pul` has its own dedicated 3-stage chain (2 stages for synchronization + 1 stage for rising-edge detection) located inside `microstep_seq`.

### 3.3 Overcurrent Guard (`oc_guard` in `rtl/oc_latch.v`)
- External comparator input `cmp_ov_c_x` (PIN_17) trips HIGH during overcurrent events.
- **Glitch Rejection:** A 4-bit digital counter (`blanking_filter.v`) requires `oc_s` to remain HIGH for 8 consecutive clock cycles (80 ns @ 100 MHz) before qualification.
- **Permanent Latch:** Once qualified, `oc_fault` is latched HIGH until system hardware reset (`rst_n` asserted LOW).

### 3.4 Microstep Sequencer (`microstep_seq` in `rtl/step_sequencer.v`)
- Detects the rising edge of `step_pul`.
- Maintains a 4-bit accumulator `step_cnt` (0 to 15) representing one full electrical revolution:
  - **16-step mode (`microstep_s = 1`):** Increments/decrements by 1 each pulse (`step_cnt ± 1`).
  - **8-step mode (`microstep_s = 0`):** Increments/decrements by 2 each pulse (`step_cnt ± 2`), visiting only even indices (0, 2, 4, 6, 8, 10, 12, 14).
  - **Direction (`dir_s`):** `0` = forward (count up), `1` = reverse (count down).
  - Counter remains frozen when `en_s = 0`. Step pulses are accepted in both Run and Hold modes.

### 3.5 Sine/Cosine LUT (`microstep_lut` in `rtl/sine_lut.v`)
- Implements spatial quadrature between Coil A and Coil B:
  - Coil A uses `OFFSET = 0` (Sine: $0^\circ$).
  - Coil B uses `OFFSET = 4` (Cosine: $90^\circ$ phase lead).
- Amplitudes are 4-bit values scaled to nearest even numbers (2, 6, 10, 12, 14). Bit 0 is held at 0 so that DAC output remains accurate even if bit 0 is omitted on hardware boards.
- Sign bits:
  - `sign_bit = 0`: Positive half-cycle ($0^\circ \le \theta < 180^\circ$).
  - `sign_bit = 1`: Negative half-cycle ($180^\circ \le \theta < 360^\circ$).

### 3.6 Reference DAC Scaling (`vref_dac` in `rtl/dac4_vref.v`)
- Selects current setpoint based on `run_hold`:
  - `run_hold = 1` (Run Mode): Full 100% current setpoint (`dac_out = dac_in`).
  - `run_hold = 0` (Hold Mode): 50% current setpoint via right-shift by 1 (`dac_out = dac_in >> 1`).
- When axis enable `en = 0`, DAC output is forced to `0000`.

### 3.7 Master Chopper Timer (`chop_timer` in `rtl/chopper_timer.v`)
- Runs a 12-bit free-running counter from `0` to `period_cycles`.
- Emits single-cycle strobe pulses:
  - `cycle_start_a` at count `0`.
  - `cycle_start_b` at count `0` (or `period_cycles >> 1` for interleaved 50% phase shift).

### 3.8 Peak-Current Mixed-Decay FSM (`hbridge_fsm` in `rtl/pwm_b_fsm.v`)
- Drives the two half-bridges per coil through 6 distinct operational states.
- See [`FSM_CHOPPER.md`](FSM_CHOPPER.md) for timing diagrams, state transitions, and mixed decay calculations.

---

## 4. IRS2111S Gate Driver Semantics

The IRS2111S is a high-voltage, high-speed half-bridge gate driver featuring:
- **Single Logic Input (`IN`):** Controls both high-side and low-side outputs.
  - `IN = 1` $\rightarrow$ High-side MOSFET ON, Low-side MOSFET OFF.
  - `IN = 0` $\rightarrow$ High-side MOSFET OFF, Low-side MOSFET ON.
- **Internal Dead Time:** Factory-trimmed to 650 ns typical (480–820 ns min/max), preventing shoot-through within each half-bridge leg.
- **Fail-Safe Clamping:** When the FPGA outputs `q1 = 0` and `q3 = 0`, both low-side MOSFETs are driven ON. This safely shorts the coil terminals to ground through the low-side Rds(on), quenching flyback currents and protecting the high-side supply rail.

---

## 5. Clocking and Reset Specifications

| Signal | Source | Frequency | Description |
| :--- | :--- | :--- | :--- |
| `sys_clk` | Internal PLL | 100 MHz (10 ns) | Main system clock for CPLD logic and RISC-V core |
| `bus_clk` | AHB bus clock | 100 MHz (10 ns) | AHB-Lite bus interface clock |
| `rst_n` | System reset | Asynchronous | Active-low hardware reset (clears registers, resets FSMs to S_OFF, resets OC latch) |
