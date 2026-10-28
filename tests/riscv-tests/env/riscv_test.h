// Minimal bare-metal environment for riscv-tests on the CG3207 core (no CSRs, no traps).
// Pass/fail is reported through the simulation exit register used by sim/tb_wrapper.v.
#ifndef _ENV_CG3207_H
#define _ENV_CG3207_H

#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp

#define SIM_EXIT_ADDR 0xFFFF00FC

#define RVTEST_CODE_BEGIN   .section .text.start; .globl _start; _start:
#define RVTEST_CODE_END     1: j 1b

#define RVTEST_PASS         li t6, SIM_EXIT_ADDR; sw zero, 0(t6); 1: j 1b
#define RVTEST_FAIL         slli a0, TESTNUM, 1; ori a0, a0, 1; li t6, SIM_EXIT_ADDR; sw a0, 0(t6); 1: j 1b

#define RVTEST_DATA_BEGIN   .data; .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END     .align 4; .global end_signature; end_signature:

#endif
