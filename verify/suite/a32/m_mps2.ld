ENTRY(Reset)
MEMORY {
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    RAM (rw)   : ORIGIN = 0x20000000, LENGTH = 4M
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    } > FLASH
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
