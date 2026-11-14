/* A-profile entry. ARM state, ARMv6, so the same file runs on
   ARM1176 and on the virt Cortex-A7 and Cortex-A15 images.
   Semihosting is svc #0x123456. */
.syntax unified
.arm

.global _start
_start:
    ldr sp, =__stack_top
    ldr r0, =__bss_start
    ldr r1, =__bss_end
    mov r2, #0
1:
    cmp r0, r1
    bhs 2f
    str r2, [r0], #4
    b 1b
2:
#ifdef RT_NEON
    /* virt leaves CP10/CP11 off. The first VLD1 is then an undefined
       instruction, and with no UND vector the guest spins. */
.fpu neon-vfpv4
    mrc p15, 0, r0, c1, c0, 2
    orr r0, r0, #0x00F00000
    mcr p15, 0, r0, c1, c0, 2
    isb
    mov r0, #0x40000000
    vmsr fpexc, r0
#endif
#ifdef RT_PMU
    /* ARMv7 cycle counter. If it stays put, the bench prints N/A. */
    mrc p15, 0, r0, c9, c14, 0
    orr r0, r0, #1
    mcr p15, 0, r0, c9, c14, 0
    mov r0, #0x80000000
    mcr p15, 0, r0, c9, c12, 1
    mrc p15, 0, r0, c9, c12, 0
    orr r0, r0, #5
    mcr p15, 0, r0, c9, c12, 0
#endif
#ifdef RT_PMU6
    /* ARM1176 cycle counter, CP15 c15. Not the ARMv7 c9 PMU. */
    mov r0, #5
    mcr p15, 0, r0, c15, c12, 0
#endif
    bl main
    mov r0, #0
    bl sh_exit

.global sh_write0
sh_write0:
    mov r1, r0
    mov r0, #4
    svc #0x123456
    bx lr

.global sh_elapsed
sh_elapsed:
    /* SYS_ELAPSED. r0 is an 8-byte buffer. QEMU writes host nanoseconds. */
    mov r1, r0
    mov r0, #0x30
    svc #0x123456
    bx lr

.global sh_exit
sh_exit:
    cmp r0, #0
    beq 1f
    ldr r1, =0x20023
    b 2f
1:
    ldr r1, =0x20026
2:
    mov r0, #0x18
    svc #0x123456
    b .
.ltorg
