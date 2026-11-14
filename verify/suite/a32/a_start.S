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
    bl main
    mov r0, #0
    bl sh_exit

.global sh_write0
sh_write0:
    mov r1, r0
    mov r0, #4
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
