/* Programs that run from DDR2 (cached region). The bootloader jumps to _start. */
MEMORY { DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 64M }
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > DDR
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > DDR
  .data : { *(.data .data.* .sdata .sdata.*) } > DDR
  .bss (NOLOAD) : { __bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(16); __bss_end = .; } > DDR
  __heap_start = ALIGN(16);
  __heap_end   = ORIGIN(DDR) + LENGTH(DDR) - 0x100000;   /* top 1 MB: stack */
  __stack_top  = ORIGIN(DDR) + LENGTH(DDR);
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
