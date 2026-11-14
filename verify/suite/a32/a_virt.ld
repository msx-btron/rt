ENTRY(_start)
MEMORY {
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 64M
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
SECTIONS {
    . = ORIGIN(RAM);
    .text : {
        *(.text*)
        *(.rodata*)
    } > RAM
    .bss : {
        . = ALIGN(4096);
        __bss_start = .;
        *(.bss.page)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM
}
