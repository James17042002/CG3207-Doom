// Bootloader: runs from the 16 KB boot RAM at reset and loads programs/data over the UART.
//
// Protocol (all multi-byte values little-endian; the host side is doom/tools/load.py):
//   'P'                          -> 'B'                      ping
//   'W' addr len data[len] sum   -> 'K' (ok) or 'E' (bad checksum)
//        writes len bytes at addr. DDR2 addresses (0x8xxxxxxx) are written through the
//        uncached alias so the data is in DDR2 before the program runs.
//   'C' addr len                 -> sum (4 bytes)            checksum of memory, for verifying
//   'J' addr                     -> 'J', then jumps to addr
// sum: c = rotl(c, 1) + byte over all bytes, starting from c = 0.
//
// Switch 15 up at reset: skip the loader and run the program already in DDR2 at 0x80000000.
#include "mmio.h"

static uint32_t get32(void) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) v |= (uint32_t)uart_getc() << (8 * i);
    return v;
}
static void put32(uint32_t v) { for (int i = 0; i < 4; i++) uart_putc((char)(v >> (8 * i))); }
static inline uint32_t step(uint32_t c, uint32_t b) { return ((c << 1) | (c >> 31)) + b; }
static inline uint32_t phys(uint32_t a) {           // DDR2 cached view -> uncached alias
    return ((a >> 27) == 0x10) ? (a | 0x40000000u) : a;
}

int main(void) {
    LEDS = 0x0001;
    SEVENSEG = 0xB0070000;
    uart_puts("\r\nCG3207 RISC-V boot\r\n");
    while (!DDR_READY) ;
    LEDS = 0x0003;
    if (DIPS & 0x8000) {
        uart_puts("SW15 up: running program in DDR2\r\n");
        uart_flush();
        ((void (*)(void))0x80000000u)();
    }
    uart_puts("ready\r\n");
    for (;;) {
        int cmd = uart_getc();
        if (cmd == 'P') {
            uart_putc('B');
        } else if (cmd == 'W') {
            uint32_t addr = phys(get32()), len = get32(), c = 0;
            SEVENSEG = addr;
            // byte stores for the unaligned head/tail, word stores otherwise
            uint32_t i = 0;
            while (i < len && (addr + i) & 3) { uint32_t b = uart_getc(); c = step(c, b); *(volatile uint8_t *)(addr + i) = b; i++; }
            while (i + 4 <= len) {
                uint32_t b0 = uart_getc(), b1 = uart_getc(), b2 = uart_getc(), b3 = uart_getc();
                c = step(step(step(step(c, b0), b1), b2), b3);
                *(volatile uint32_t *)(addr + i) = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
                i += 4;
            }
            while (i < len) { uint32_t b = uart_getc(); c = step(c, b); *(volatile uint8_t *)(addr + i) = b; i++; }
            uart_putc(get32() == c ? 'K' : 'E');
            LEDS ^= 0x8000;
        } else if (cmd == 'C') {
            uint32_t addr = phys(get32()), len = get32(), c = 0;
            for (uint32_t i = 0; i < len; i++) c = step(c, *(volatile uint8_t *)(addr + i));
            put32(c);
        } else if (cmd == 'J') {
            uint32_t addr = get32();
            uart_putc('J');
            uart_flush();
            LEDS = 0x0007;
            ((void (*)(void))addr)();
        }
    }
}
