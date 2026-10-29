# AHB Register Map and Firmware API Specification

The AGM AG32 CPLD logic core is memory-mapped to the 32-bit AHB-Lite bus of the RISC-V microcontroller core at base address `0x60000000`.

---

## 1. Register Address Map

All registers are 32-bit word-aligned (`mem_ahb_haddr[4:2]` address decoding).

| Byte Offset | Register Name | Bitfields | Access | Reset Value | Physical Equivalent (@ 100 MHz) |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **`0x00`** | `dead_cycles` | `[7:0]` | R/W | `79` (`0x4F`) | **800 ns** software dead-time margin |
| **`0x04`** | `fast_cycles` | `[11:0]` | R/W | `499` (`0x1F3`) | **5.0 $\mu\text{s}$** active fast-decay reverse quench |
| **`0x08`** | `slow_cycles` | `[11:0]` | R/W | `1499` (`0x5DB`) | **15.0 $\mu\text{s}$** recirculating slow decay |
| **`0x0C`** | `period_cycles` | `[11:0]` | R/W | `3332` (`0xD04`) | **33.33 $\mu\text{s}$** period (**30.00 kHz** chopper frequency) |

---

## 2. Register Descriptions & Conversion Formulas

### 2.1 Software Dead-Time Margin (`dead_cycles`, Offset `0x00`)
- **Bits:** `[7:0]` (Bits `[31:8]` reserved / write ignored, reads 0).
- **Function:** Controls the duration of `S_DT_ON` and `S_DT_OFF` states where both high-side FETs are off and low-side FETs are on.
- **Conversion Formula:**
  $$T_{\text{dead}} = (\text{dead\_cycles} + 1) \times 10\text{ ns}$$
  $$\text{dead\_cycles} = \left(\frac{T_{\text{dead}}}{10\text{ ns}}\right) - 1$$

---

### 2.2 Fast Decay Duration (`fast_cycles`, Offset `0x04`)
- **Bits:** `[11:0]` (Bits `[31:12]` reserved / write ignored, reads 0).
- **Function:** Controls how long the H-bridge actively applies reverse DC bus voltage across the coil to rapidly extinguish inductive energy.
- **Conversion Formula:**
  $$T_{\text{fast}} = (\text{fast\_cycles} + 1) \times 10\text{ ns}$$
  $$\text{fast\_cycles} = \left(\frac{T_{\text{fast}}}{10\text{ ns}}\right) - 1$$

---

### 2.3 Slow Decay Duration (`slow_cycles`, Offset `0x08`)
- **Bits:** `[11:0]` (Bits `[31:12]` reserved / write ignored, reads 0).
- **Function:** Controls the duration of the freewheeling recirculating phase through both bottom MOSFETs.
- **Conversion Formula:**
  $$T_{\text{slow}} = (\text{slow\_cycles} + 1) \times 10\text{ ns}$$
  $$\text{slow\_cycles} = \left(\frac{T_{\text{slow}}}{10\text{ ns}}\right) - 1$$

---

### 2.4 Master Chopper Period (`period_cycles`, Offset `0x0C`)
- **Bits:** `[11:0]` (Bits `[31:12]` reserved / write ignored, reads 0).
- **Function:** Sets the total cycle length of the PWM chopper timer shared by Coil A and Coil B.
- **Conversion Formulas:**
  $$T_{\text{period}} = (\text{period\_cycles} + 1) \times 10\text{ ns}$$
  $$f_{\text{chop}} = \frac{100\text{ MHz}}{\text{period\_cycles} + 1}$$
  $$\text{period\_cycles} = \left(\frac{100\text{ MHz}}{f_{\text{chop}}}\right) - 1$$

---

## 3. C Firmware Implementation Reference

The configuration can be handled using macros defined in [`src/main.h`](../src/main.h) and executed in [`src/main.c`](../src/main.c):

```c
#include "main.h"

#define CPLD_BASE            0x60000000UL
#define REG_DEAD_CYCLES      0x00
#define REG_FAST_CYCLES      0x04
#define REG_SLOW_CYCLES      0x08
#define REG_PERIOD_CYCLES    0x0C

#define CPLD_WRITE(offset, val)  (*(volatile uint32_t *)((CPLD_BASE) + (offset)) = (uint32_t)(val))
#define CPLD_READ(offset)        (*(volatile uint32_t *)((CPLD_BASE) + (offset)))

/**
 * @brief Configure chopper parameters dynamically from RISC-V firmware.
 * @param dead_ns    Dead-time margin in nanoseconds (e.g. 800)
 * @param fast_us    Fast decay duration in microseconds (e.g. 5)
 * @param slow_us    Slow decay duration in microseconds (e.g. 15)
 * @param chop_freq_hz Chopper frequency in Hertz (e.g. 30000)
 */
void stepper_set_timing(uint32_t dead_ns, uint32_t fast_us, uint32_t slow_us, uint32_t chop_freq_hz)
{
    uint32_t dead_val   = (dead_ns / 10u) - 1u;
    uint32_t fast_val   = (fast_us * 100u) - 1u;
    uint32_t slow_val   = (slow_us * 100u) - 1u;
    uint32_t period_val = (100000000u / chop_freq_hz) - 1u;

    CPLD_WRITE(REG_DEAD_CYCLES,   dead_val);
    CPLD_WRITE(REG_FAST_CYCLES,   fast_val);
    CPLD_WRITE(REG_SLOW_CYCLES,   slow_val);
    CPLD_WRITE(REG_PERIOD_CYCLES, period_val);
}
```
