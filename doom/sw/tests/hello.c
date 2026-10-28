#include "mmio.h"
volatile int a = 1234, b = 56;
int arr[1000];
int main(void) {
    uart_puts("Hello from DDR2!\n");
    int p = a * b, q = a / b, r = a % b;
    SEVENSEG = p;
    for (int i = 0; i < 1000; i++) arr[i] = i * 3;
    int s = 0;
    for (int i = 0; i < 1000; i++) s += arr[i];
    uart_puts("sum=0x"); uart_puthex(s); uart_putc('\n');
    return (p == 69104 && q == 22 && r == 2 && s == 1498500) ? 0 : 1;
}
