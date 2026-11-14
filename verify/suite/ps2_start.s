/* PCSX2 enters at _start in kernel mode. BSS is cleared, then main. */
.set noreorder
.set noat

.section .text.startup, "ax", @progbits
.p2align 4
.globl _start
_start:
    lui $sp, 0x01FF
    la $gp, _gp
    la $t0, __bss_start
    la $t1, _end
1:
    beq $t0, $t1, 2f
    nop
    sw $zero, 0($t0)
    addiu $t0, $t0, 4
    b 1b
    nop
2:
    jal main
    nop
3:
    b 3b
    nop
