#ifndef MMIO_H
#define MMIO_H
#include <stdint.h>
#define MMIO(off) (*(volatile uint32_t *)(0xFFFF0000u + (off)))
#define UART_RX_VALID MMIO(0x00)
#define UART_RX       MMIO(0x04)
#define UART_TX_READY MMIO(0x08)
#define UART_TX       MMIO(0x0C)
#define OLED_COL      MMIO(0x20)
#define OLED_ROW      MMIO(0x24)
#define OLED_DATA     MMIO(0x28)
#define OLED_CTRL     MMIO(0x2C)
#define LEDS          MMIO(0x60)
#define DIPS          MMIO(0x64)
#define PBS           MMIO(0x68)
#define SEVENSEG      MMIO(0x80)
#define CYCLECOUNT    MMIO(0xA0)
#define SIM_EXIT      MMIO(0xFC)   /* simulation only */

static inline void uart_putc(char c) { while (!UART_TX_READY) ; UART_TX = (uint8_t)c; }
static inline void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
#endif
