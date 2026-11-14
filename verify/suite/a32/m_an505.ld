ENTRY(Reset)
MEMORY {
    FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 512K
    RAM (rw)   : ORIGIN = 0x80000000, LENGTH = 1M
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
