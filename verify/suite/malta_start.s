/* Malta kernel entry. Stack is 8 MiB into kseg0 RAM. BSS is cleared
   from C so this file does not materialize a 64-bit symbol address. */
.set noreorder
.set noat

.section .text.startup, "ax", @progbits
.globl _start
_start:
    lui $sp, 0x8080
    jal main
    nop
1:
    b 1b
    nop
