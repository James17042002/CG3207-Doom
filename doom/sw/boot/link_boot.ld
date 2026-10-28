MEMORY { BOOT (rwx) : ORIGIN = 0x00000000, LENGTH = 16K }
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > BOOT
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > BOOT
  .data : { *(.data .data.* .sdata .sdata.*) } > BOOT
  .bss (NOLOAD) : { __bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); __bss_end = .; } > BOOT
  __stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
