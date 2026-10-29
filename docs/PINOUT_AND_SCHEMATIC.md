# Hardware Pinout and Circuit Interface Guide

This document details the hardware pin mapping, external driver connections, R-2R DAC ladder calculations, and analog comparator design for the **AG32VF303** 1-Axis Stepper Driver.

---

## 1. Pin Mapping Table (`mapping.ve`)

All CPLD pin assignments are mapped according to `mapping.ve` for the AGM AG32VF303 (LQFP-48 / 100-pin package):

### Control & Status Inputs

| Signal Name | Pin No. | Direction | Pull Mode | Electrical Level | Functional Description |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `axis_en` | **PIN_1** | Input | None | 3.3V CMOS | **Axis Enable:** HIGH = enabled; LOW = disabled (all FETs off/low-side clamped). |
| `pul_x` | **PIN_96** | Input | **PULLUP** | 3.3V CMOS | **Step Pulse:** Rising edge advances step counter by 1 microstep. |
| `dir_x` | **PIN_15** | Input | None | 3.3V CMOS | **Step Direction:** LOW = Forward (count up); HIGH = Reverse (count down). |
| `runhold_x` | **PIN_78** | Input | **PULLUP** | 3.3V CMOS | **Current Mode:** HIGH = Run mode (100% current); LOW = Hold mode (50% current). |
| `microstep_x` | **PIN_16** | Input | None | 3.3V CMOS | **Microstepping Mode:** HIGH = 16-step mode; LOW = 8-step mode. |
| `cmp_ov_c_x` | **PIN_17** | Input | **PULLDOWN** | 3.3V CMOS | **Overcurrent Fault:** HIGH = Fault tripped. Latches off all gate outputs until reset. |

### Coil A (Phase A — Sine $0^\circ$)

| Signal Name | Pin No. | Direction | Interface | Functional Description |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_a` | **PIN_95** | Input (PULLUP) | Analog Comparator | **Chopper Comparator A (Active LOW):** LOW = coil current reached $V_{\text{ref\_A}}$. |
| `q1_x_a` | **PIN_92** | Output | IRS2111S IN_L | Left half-bridge gate input for Coil A (HIGH = high-side ON). |
| `q3_x_a` | **PIN_88** | Output | IRS2111S IN_R | Right half-bridge gate input for Coil A (HIGH = high-side ON). |
| `dac_out_x_a[3]` | **PIN_86** | Output | R-2R Ladder (MSB) | Bit 3 of 4-bit current reference DAC (Weight = 8). |
| `dac_out_x_a[2]` | **PIN_84** | Output | R-2R Ladder | Bit 2 of 4-bit current reference DAC (Weight = 4). |
| `dac_out_x_a[1]` | **PIN_82** | Output | R-2R Ladder | Bit 1 of 4-bit current reference DAC (Weight = 2). |
| `dac_out_x_a[0]` | **PIN_80** | Output | R-2R Ladder (LSB) | Bit 0 of 4-bit current reference DAC (Weight = 1). |

### Coil B (Phase B — Cosine $90^\circ$)

| Signal Name | Pin No. | Direction | Interface | Functional Description |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_b` | **PIN_93** | Input (PULLUP) | Analog Comparator | **Chopper Comparator B (Active LOW):** LOW = coil current reached $V_{\text{ref\_B}}$. |
| `q1_x_b` | **PIN_91** | Output | IRS2111S IN_L | Left half-bridge gate input for Coil B (HIGH = high-side ON). |
| `q3_x_b` | **PIN_87** | Output | IRS2111S IN_R | Right half-bridge gate input for Coil B (HIGH = high-side ON). |
| `dac_out_x_b[3]` | **PIN_85** | Output | R-2R Ladder (MSB) | Bit 3 of 4-bit current reference DAC (Weight = 8). |
| `dac_out_x_b[2]` | **PIN_83** | Output | R-2R Ladder | Bit 2 of 4-bit current reference DAC (Weight = 4). |
| `dac_out_x_b[1]` | **PIN_81** | Output | R-2R Ladder | Bit 1 of 4-bit current reference DAC (Weight = 2). |
| `dac_out_x_b[0]` | **PIN_79** | Output | R-2R Ladder (LSB) | Bit 0 of 4-bit current reference DAC (Weight = 1). |

---

## 2. Gate Driver Interface (IRS2111S)

The power stage utilizes two IRS2111S gate driver ICs per motor coil (four ICs total):

```
                       +-------------------+
         q1_x_a ------>| IN                |
                       |                   |
                       |          IRS2111S |-----> HO ----> Q14 Gate (High-Side)
                       |                   |-----> VS ----> Motor Phase A+
                       |                   |-----> LO ----> Q16 Gate (Low-Side)
                       |  (Left Leg A)     |
                       +-------------------+

                       +-------------------+
         q3_x_a ------>| IN                |
                       |                   |
                       |          IRS2111S |-----> HO ----> Q13 Gate (High-Side)
                       |                   |-----> VS ----> Motor Phase A-
                       |                   |-----> LO ----> Q15 Gate (Low-Side)
                       |  (Right Leg A)    |
                       +-------------------+
```

### Truth Table per Half-Bridge Leg

| Input Pin (`IN`) | High-Side Output (`HO`) | Low-Side Output (`LO`) | Half-Bridge State |
| :---: | :---: | :---: | :--- |
| **`1`** | **HIGH** ($V_S + V_{BS}$) | **LOW** (GND) | High-Side MOSFET ON, Low-side OFF |
| **`0`** | **LOW** ($V_S$) | **HIGH** ($V_{CC}$) | High-Side MOSFET OFF, Low-side ON |

> [!IMPORTANT]
> Because `IN = 0` turns the low-side switch ON, setting both `q1 = 0` and `q3 = 0` puts the full H-bridge into low-side recirculating freewheel mode. This safely clamps motor inductive spikes to ground without requiring dedicated shutdown pins.

---

## 3. 4-bit R-2R Ladder DAC Calculation

The reference voltage for each coil comparator is generated using a discrete 4-bit R-2R resistor ladder (e.g., $R = 10\text{ k}\Omega, 2R = 20\text{ k}\Omega$ with $1\%$ tolerance):

$$V_{\text{ref}} = V_{DDIO} \times \frac{\text{DAC\_OUT}}{16} \quad (V_{DDIO} = 3.3\text{ V})$$

| DAC Code | Binary | Amplitude Fraction | Theoretical $V_{\text{ref}}$ | Mode / Phase Angle |
| :---: | :---: | :---: | :---: | :--- |
| **0** | `0000` | $0.0000$ | $0.000\text{ V}$ | Driver Disabled (`en_x = 0`) |
| **2** | `0010` | $0.1250$ | $0.413\text{ V}$ | $0^\circ$ / $180^\circ$ Minimum bias (no zero stall) |
| **6** | `0110` | $0.3750$ | $1.238\text{ V}$ | $22.5^\circ$ / $157.5^\circ$ / $202.5^\circ$ / $337.5^\circ$ |
| **10** | `1010` | $0.6250$ | $2.063\text{ V}$ | $45^\circ$ / $135^\circ$ / $225^\circ$ / $315^\circ$ |
| **12** | `1100` | $0.7500$ | $2.475\text{ V}$ | $67.5^\circ$ / $112.5^\circ$ / $247.5^\circ$ / $292.5^\circ$ |
| **14** | `1110` | $0.8750$ | $2.888\text{ V}$ | $90^\circ$ / $270^\circ$ Peak Sine/Cosine amplitude |

### Current Sensing Shunt Resistor Sizing

With a current sense resistor $R_{\text{sense}}$ on the low-side return:

$$I_{\text{peak}} = \frac{V_{\text{ref}}}{R_{\text{sense}}}$$

For example, to achieve a maximum peak motor current of $2.5\text{ A}$ at $V_{\text{ref\_peak}} = 2.888\text{ V}$ (attenuated through a 1:10 resistive divider before comparator input):
$$V_{\text{sense\_target}} = 0.2888\text{ V} \implies R_{\text{sense}} = \frac{0.2888\text{ V}}{2.5\text{ A}} \approx 0.115\text{ }\Omega \text{ (e.g. } 0.1\text{ }\Omega \text{, } 2\text{ W)}$$

---

## 4. Overcurrent Comparator Design

The overcurrent comparator (`cmp_ov_c_x` on PIN_17) monitors the total DC link return current:
- **Threshold:** Typically set to $150\% \text{ to } 200\%$ of maximum rated motor peak current.
- **Normal Operation:** Comparator output is LOW (`0`).
- **Overcurrent Event:** Comparator output transitions HIGH (`1`).
- **FPGA Filtering:** The on-chip `blanking_filter` rejects transient spikes shorter than $80\text{ ns}$ (8 clock cycles @ 100 MHz).
- **Latching:** If the fault condition persists for $\ge 80\text{ ns}$, `oc_fault` latches HIGH, disabling all high-side drive and clamping all low-side switches.
