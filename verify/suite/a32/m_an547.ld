ENTRY(Reset)
MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
SECTIONS {
    . = ORIGIN(RAM);
    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    } > RAM
    .bss : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss.page)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM
}
