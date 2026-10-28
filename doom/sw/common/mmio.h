// Peripherals of the doom SoC (doom/rtl/mmio.v).
#ifndef MMIO_H
#define MMIO_H
#include <stdint.h>

#define MMIO_BASE 0xFFFF0000u
#define MMIO(off) (*(volatile uint32_t *)(MMIO_BASE + (off)))
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
#define TIMER_MS      MMIO(0xA4)
#define TIMER_US      MMIO(0xA8)
#define DDR_READY     MMIO(0xAC)
#define SIM_EXIT      MMIO(0xFC)   /* simulation only */

#define PB_LEFT   (1u << 0)
#define PB_CENTER (1u << 1)
#define PB_RIGHT  (1u << 2)
#define PB_UP     (1u << 3)
#define PB_DOWN   (1u << 4)

#define DDR_CACHED   0x80000000u
#define DDR_UNCACHED 0xC0000000u
#define DDR_SIZE     0x08000000u

static inline void uart_putc(char c) { while (!(UART_TX_READY & 1)) ; UART_TX = (uint8_t)c; }
static inline void uart_flush(void) { while (!(UART_TX_READY & 2)) ; }
static inline void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
static inline int  uart_getc_nb(void) { return UART_RX_VALID ? (int)(UART_RX & 0xFF) : -1; }
static inline int  uart_getc(void) { while (!UART_RX_VALID) ; return (int)(UART_RX & 0xFF); }
static inline void uart_puthex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 15]);
}
#endif
