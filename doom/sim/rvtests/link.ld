MEMORY { DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > DDR
  .data : { . = ALIGN(16); *(.rodata*) *(.data .data.* .sdata*) *(.sbss* .bss* COMMON) } > DDR
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
