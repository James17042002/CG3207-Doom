#include "mmio.h"
// Toolchain smoke test: prints over UART, does a multiply and divide, shows the result on the 7-seg.
volatile int a = 1234, b = 56;
int main(void) {
    uart_puts("Hello from C!\n");
    int p = a * b, q = a / b, r = a % b;
    SEVENSEG = p;
    return (p == 69104 && q == 22 && r == 2) ? 0 : 1;
}
