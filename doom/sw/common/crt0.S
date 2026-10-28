# Startup for programs in DDR2: stack, clear .bss, main(), exit code to the sim exit register.
    .section .text.start
    .globl _start
_start:
    la   sp, __stack_top
    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:  li   a0, 0
    li   a1, 0
    call main
    .globl _exit
_exit:
    li   t0, 0xFFFF0008      # wait until the UART has sent everything
4:  lw   t1, 0(t0)
    andi t1, t1, 2
    beqz t1, 4b
    li   t0, 0xFFFF00FC
    sw   a0, 0(t0)
3:  j    3b
