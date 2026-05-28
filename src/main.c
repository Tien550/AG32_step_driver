#include "main.h"

// AHB Register Map — CPLD base address 0x60000000
//   0x00: dead_cycles   [7:0]   — software dead time (both coils)
//   0x04: fast_cycles   [11:0]  — fast decay duration (both coils)
//   0x08: slow_cycles   [11:0]  — slow decay duration (both coils)
//   0x0C: period_cycles [11:0]  — chopper period (both coils)
//
// Hardware pins (not AHB):
//   runhold_x   (PIN_78): 1=run 100% LUT, 0=hold 50% LUT (default PULLUP=run)
//   microstep_x (PIN_16): 1=16-step, 0=8-step
//   cmp_ov_c_x  (PIN_17): OC comparator active-HIGH, 80 ns blanking, PULLDOWN

int main(void)
{
    board_init();
    INT_SetIRQThreshold(MIN_IRQ_PRIORITY);
    INT_EnableIRQ(BUT_GPIO_IRQ, PLIC_MAX_PRIORITY);

    WR(0x00, 79u);   // dead_cycles   — 800 ns dead time   (= 80-1)
    WR(0x04, 499u);  // fast_cycles   — 5 µs fast decay   (= 500-1)
    WR(0x08, 1499u); // slow_cycles   — 15 µs slow decay  (= 1500-1)
    WR(0x0C, 3332u); // period_cycles — 30 kHz chopper    (= 3333-1)

}