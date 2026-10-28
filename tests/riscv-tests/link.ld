MEMORY {
  IROM (rx) : ORIGIN = 0x00400000, LENGTH = 16K
  DMEM (rw) : ORIGIN = 0x10010000, LENGTH = 16K
}
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > IROM
  .data : { *(.rodata*) *(.data .data.* .sdata*) *(.sbss* .bss* COMMON) } > DMEM
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
