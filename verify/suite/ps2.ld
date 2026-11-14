/* Emotion Engine RAM. PCSX2 loads this ELF at 0x00100000. The stack
   sits 64 KiB below the 32 MiB RDRAM end. */
ENTRY(_start)

SECTIONS
{
    . = 0x00100000;

    .text : {
        *(.text.startup)
        *(.text)
        *(.text.*)
    }

    . = ALIGN(128);
    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    . = ALIGN(128);
    .data : {
        _gp = ALIGN(16) + 0x7ff0;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    }

    . = ALIGN(4096);
    __bss_start = .;
    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    }
    . = ALIGN(16);
    _end = .;

    ASSERT(_end <= 0x01F00000,
           "PS2 image reaches the stack")
}
