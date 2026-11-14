ENTRY(_start)
MEMORY {
    RAM (rwx) : ORIGIN = 0x8000, LENGTH = 32M
}
__stack_top = 0x02000000;
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
