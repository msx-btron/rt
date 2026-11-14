/* QEMU Malta, kseg0. The entry is the sign-extended address so a
   64-bit R4000 fetch does not take an address error. */
ENTRY(_start)

SECTIONS
{
    . = 0xffffffff80010000;

    .text : {
        *(.text.startup)
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .data : {
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

    /DISCARD/ : {
        *(.reginfo)
        *(.MIPS.abiflags)
        *(.MIPS.options)
        *(.pdr)
        *(.comment)
        *(.gnu.attributes)
    }
}
