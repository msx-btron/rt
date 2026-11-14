/* Thumb reset for Cortex-M. BSS clear is two instructions because
   post-index str is Thumb-2 and faults on Cortex-M0. Semihosting
   is bkpt 0xAB. QEMU does not zero BSS. */
.syntax unified
.thumb

.section .vectors, "a"
.word __stack_top
.word Reset

.section .text
.thumb_func
.global Reset
Reset:
#ifdef RT_CPACR
    ldr r0, =0xE000ED88
    ldr r1, [r0]
    ldr r2, =0x00F00000
    orrs r1, r2
    str r1, [r0]
    dsb
    isb
#endif
#ifdef RT_DWT
    /* DEMCR.TRCENA, then DWT_CTRL.CYCCNTENA. A stuck CYCCNT stays N/A. */
    ldr r0, =0xE000EDFC
    ldr r1, [r0]
    movs r2, #1
    lsls r2, r2, #24
    orrs r1, r2
    str r1, [r0]
    ldr r0, =0xE0001000
    ldr r1, [r0]
    movs r2, #1
    orrs r1, r2
    str r1, [r0]
#endif
    ldr r0, =__bss_start
    ldr r1, =__bss_end
    movs r2, #0
1:
    cmp r0, r1
    bhs 2f
    str r2, [r0]
    adds r0, r0, #4
    b 1b
2:
    bl main
    movs r0, #0
    bl sh_exit

.thumb_func
.global sh_write0
sh_write0:
    mov r1, r0
    movs r0, #4
    bkpt 0xAB
    bx lr

.thumb_func
.global sh_exit
sh_exit:
    cmp r0, #0
    beq 1f
    ldr r1, =0x20023
    b 2f
1:
    ldr r1, =0x20026
2:
    movs r0, #0x18
    bkpt 0xAB
    b .
.ltorg
