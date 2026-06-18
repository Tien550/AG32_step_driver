#ifndef MAIN_H
#define MAIN_H

#include "board.h"
#include <stdint.h>

#define CPLD_BASE  0x60000000UL
#define WR(offset, value)  (*(volatile uint32_t *)((CPLD_BASE) + (offset)) = (uint32_t)(value))

#ifndef MSG_UART_ID
#define MSG_UART_ID 1
#endif

#ifndef BAUD_RATE
#define BAUD_RATE 500000
#endif

#define MIN_IRQ_PRIORITY 1
#define MAX_IRQ_PRIORITY PLIC_MAX_PRIORITY

#define I2C_PRIORITY    (MIN_IRQ_PRIORITY + 1)
#define TIMER_PRIORITY  (MIN_IRQ_PRIORITY + 2)
#define DMAC_PRIORITY   (MIN_IRQ_PRIORITY + 8)
#define UART_PRIORITY   (MIN_IRQ_PRIORITY + 9)
#define CAN_PRIORITY    (MIN_IRQ_PRIORITY + 7)
#define RTC_PRIORITY    (MIN_IRQ_PRIORITY + 6)
#define EXT_PRIORITY    (MIN_IRQ_PRIORITY + 4)
#define SPI_PRIORITY    (MIN_IRQ_PRIORITY + 5)
#define MEMSPI_PRIORITY (MIN_IRQ_PRIORITY + 1)
#define GPIO_PRIORITY   (MIN_IRQ_PRIORITY + 1)
#define FLASH_PRIORITY  (MAX_IRQ_PRIORITY - 5)
#define USB_PRIORITY    (MAX_IRQ_PRIORITY - 1)
#define MAC_PRIORITY    (MAX_IRQ_PRIORITY - 1)
#define WDOG_PRIORITY   (MAX_IRQ_PRIORITY - 0)

__attribute__((weak)) void (*button_isr_cb)(void);

#define WAIT_UART { if (MSG_UART) while (UART_IsTxBusy(MSG_UART)); }

#endif