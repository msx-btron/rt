/* AArch64 Advanced SIMD.
   Unaligned ldr/str q is one issue on v8, so there is no align head.
   64-byte unroll keeps four q registers in flight.
   Tails are GPR and never read past n.
   Darwin C symbols carry a leading underscore; Linux does not. */

.text

#if defined(__APPLE__)
#define SYM(name) _##name
#else
#define SYM(name) name
#endif

.globl SYM(rt_memcpy_neon)
#ifndef __APPLE__
.type SYM(rt_memcpy_neon), %function
#endif
.p2align 4
SYM(rt_memcpy_neon):
    mov x8, x0
    cmp x2, #64
    b.lo .Lmc_16
.p2align 4
.Lmc_64:
    ldp q0, q1, [x1]
    ldp q2, q3, [x1, #32]
    add x1, x1, #64
    stp q0, q1, [x0]
    stp q2, q3, [x0, #32]
    add x0, x0, #64
    sub x2, x2, #64
    cmp x2, #64
    b.hs .Lmc_64
.Lmc_16:
    cmp x2, #16
    b.lo .Lmc_8
    ldr q0, [x1], #16
    str q0, [x0], #16
    sub x2, x2, #16
    b .Lmc_16
.Lmc_8:
    cmp x2, #8
    b.lo .Lmc_4
    ldr x9, [x1], #8
    str x9, [x0], #8
    sub x2, x2, #8
.Lmc_4:
    cmp x2, #4
    b.lo .Lmc_2
    ldr w9, [x1], #4
    str w9, [x0], #4
    sub x2, x2, #4
.Lmc_2:
    cmp x2, #2
    b.lo .Lmc_1
    ldrh w9, [x1], #2
    strh w9, [x0], #2
    sub x2, x2, #2
.Lmc_1:
    cbz x2, .Lmc_ret
    ldrb w9, [x1]
    strb w9, [x0]
.Lmc_ret:
    mov x0, x8
    ret

.globl SYM(rt_memset_neon)
#ifndef __APPLE__
.type SYM(rt_memset_neon), %function
#endif
.p2align 4
SYM(rt_memset_neon):
    mov x8, x0
    and w1, w1, #0xff
    orr w1, w1, w1, lsl #8
    orr w1, w1, w1, lsl #16
    orr x3, x1, x1, lsl #32
    dup v0.2d, x3
    cmp x2, #64
    b.lo .Lms_16
.p2align 4
.Lms_64:
    stp q0, q0, [x0]
    stp q0, q0, [x0, #32]
    add x0, x0, #64
    sub x2, x2, #64
    cmp x2, #64
    b.hs .Lms_64
.Lms_16:
    cmp x2, #16
    b.lo .Lms_8
    str q0, [x0], #16
    sub x2, x2, #16
    b .Lms_16
.Lms_8:
    cmp x2, #8
    b.lo .Lms_4
    str x3, [x0], #8
    sub x2, x2, #8
.Lms_4:
    cmp x2, #4
    b.lo .Lms_2
    str w3, [x0], #4
    sub x2, x2, #4
.Lms_2:
    cmp x2, #2
    b.lo .Lms_1
    strh w3, [x0], #2
    sub x2, x2, #2
.Lms_1:
    cbz x2, .Lms_ret
    strb w3, [x0]
.Lms_ret:
    mov x0, x8
    ret

.globl SYM(rt_memcmp_neon)
#ifndef __APPLE__
.type SYM(rt_memcmp_neon), %function
#endif
.p2align 4
SYM(rt_memcmp_neon):
    cmp x2, #16
    b.lo .Lmp_b
.p2align 4
.Lmp_16:
    ldr q0, [x0], #16
    ldr q1, [x1], #16
    cmeq v2.16b, v0.16b, v1.16b
    uminv b3, v2.16b
    umov w9, v3.b[0]
    cmp w9, #0xff
    b.ne .Lmp_scan
    sub x2, x2, #16
    cmp x2, #16
    b.hs .Lmp_16
    b .Lmp_b
.Lmp_scan:
    sub x0, x0, #16
    sub x1, x1, #16
.Lmp_b:
    cbz x2, .Lmp_eq
.Lmp_loop:
    ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    subs w9, w9, w10
    b.ne .Lmp_ret
    subs x2, x2, #1
    b.ne .Lmp_loop
.Lmp_eq:
    mov w0, #0
    ret
.Lmp_ret:
    mov w0, w9
    ret
