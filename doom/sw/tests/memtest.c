// Cache / DDR2 stress test: eviction with dirty write-back, byte/halfword stores,
// store->load forwarding, uncached alias, conflicting addresses.
#include "mmio.h"
#define N (48 * 1024)                 // words: 192 KB, much larger than the 16 KB D-cache
static uint32_t big[N];
static volatile uint8_t bytes[4096];

static uint32_t lcg(uint32_t x) { return x * 1664525u + 1013904223u; }
static int fails = 0;
static void check(int ok, const char *what, uint32_t got, uint32_t exp) {
    if (!ok) { fails++; uart_puts("FAIL "); uart_puts(what); uart_puts(" got "); uart_puthex(got);
               uart_puts(" exp "); uart_puthex(exp); uart_putc('\n'); }
}

int main(void) {
    uart_puts("memtest\n");
    // 1. sequential write, read back (evicts dirty lines many times)
    uint32_t x = 1;
    for (int i = 0; i < N; i++) { x = lcg(x); big[i] = x; }
    x = 1;
    for (int i = 0; i < N; i++) { x = lcg(x); if (big[i] != x) { check(0, "seq", big[i], x); break; } }
    // 2. random-order read-modify-write
    x = 7;
    for (int k = 0; k < 20000; k++) { x = lcg(x); int i = (x >> 8) % N; big[i] ^= (uint32_t)i * 2654435761u; }
    x = 7;
    for (int k = 0; k < 20000; k++) { x = lcg(x); int i = (x >> 8) % N; big[i] ^= (uint32_t)i * 2654435761u; }
    x = 1;
    for (int i = 0; i < N; i++) { x = lcg(x); if (big[i] != x) { check(0, "rmw", big[i], x); break; } }
    // 3. byte and halfword stores, immediately read back
    for (int i = 0; i < 4096; i++) { bytes[i] = (uint8_t)(i * 7); if (bytes[i] != (uint8_t)(i * 7)) { check(0, "byte", bytes[i], (uint8_t)(i*7)); break; } }
    volatile uint16_t *h = (volatile uint16_t *)bytes;
    for (int i = 0; i < 2048; i++) h[i] = (uint16_t)(i * 13 + 1);
    for (int i = 0; i < 2048; i++) if (h[i] != (uint16_t)(i * 13 + 1)) { check(0, "half", h[i], (uint16_t)(i*13+1)); break; }
    for (int i = 0; i < 4096; i += 4) if (bytes[i] != (uint8_t)((i/2) * 13 + 1)) { check(0, "half-byte", bytes[i], (uint8_t)((i/2)*13+1)); break; }
    // 4. store then load of a conflicting line (same index, different tag): forces write-back
    volatile uint32_t *a = (volatile uint32_t *)0x80200000, *b = (volatile uint32_t *)0x80210000; // 64 KB apart (cache size)
    for (int i = 0; i < 100; i++) { a[i] = i; b[i] = ~i; if (a[i] != (uint32_t)i || b[i] != (uint32_t)~i) { check(0, "conflict", a[i], i); break; } }
    // 5. uncached alias: write through 0xC..., read cold lines through 0x8...
    volatile uint32_t *u = (volatile uint32_t *)(DDR_UNCACHED + 0x00300000), *c = (volatile uint32_t *)(DDR_CACHED + 0x00300000);
    for (int i = 0; i < 256; i++) u[i] = 0xA5000000u | i;
    for (int i = 0; i < 256; i++) if (c[i] != (0xA5000000u | i)) { check(0, "uncached", c[i], 0xA5000000u | i); break; }
    for (int i = 0; i < 256; i++) if (u[i] != (0xA5000000u | i)) { check(0, "uncached-rd", u[i], 0xA5000000u | i); break; }
    uart_puts(fails ? "memtest FAILED\n" : "memtest OK\n");
    return fails;
}
