/* Memory map matching Wrapper.v (IROM_BASE, DMEM_BASE, *_DEPTH_BITS). */
MEMORY {
  IROM (rx)  : ORIGIN = 0x00400000, LENGTH = 512
  DMEM (rw)  : ORIGIN = 0x10010000, LENGTH = 512
}
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > IROM
  /* Wrapper.v has no path from IROM to the data port, so constants live in DMEM. */
  .data : { *(.rodata .rodata.* .srodata .srodata.*) *(.data .data.* .sdata .sdata.*)
            __bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON); __bss_end = .; } > DMEM
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
