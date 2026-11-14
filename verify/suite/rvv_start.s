# Freestanding entry for QEMU virt. Enables V (and F, so a stray float
# op does not trap), zeros BSS, then passes rvv_main's status to the
# SiFive test finisher at 0x100000. UART is the virt 16550 at 0x10000000.

.section .text.init
.globl _start
_start:
    li t0, 0x6600
    csrs mstatus, t0
    la sp, _stack
    la t0, __bss_start
    la t1, __bss_end
1:
    beq t0, t1, 2f
    sb zero, 0(t0)
    addi t0, t0, 1
    j 1b
2:
    call rvv_main
    beqz a0, 3f
    slli a0, a0, 16
    li t0, 0x3333
    or a0, a0, t0
    j 4f
3:
    li a0, 0x5555
4:
    li t1, 0x100000
    sw a0, 0(t1)
5:
    j 5b

.globl uart_putc
uart_putc:
    li t0, 0x10000000
1:
    lbu t1, 5(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    andi a0, a0, 255
    sb a0, 0(t0)
    ret

.globl uart_flush
uart_flush:
    li t0, 0x10000000
1:
    lbu t1, 5(t0)
    andi t1, t1, 0x40
    beqz t1, 1b
    ret

.section .bss
.align 4
.space 8192
.align 4
_stack:
