/* QEMU virt RAM, 4MB, matching scripts/riscv.sh -m 4M.
   The checker plants fault edges at 0x80400000. */
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 4M }
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) } > ram
  .rodata : { *(.rodata .rodata.*) } > ram
  .data : { *(.data .data.*) } > ram
  .bss : {
    __bss_start = .;
    *(.bss .bss.*) *(COMMON)
    __bss_end = .;
  } > ram
}
