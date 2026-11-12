/* AArch64 NEON string kernels.
   Darwin assembler: only numeric local labels (1:, 2:) for intra-fn branches. */

.text

#if defined(__APPLE__)
#define SYM(name) _##name
#else
#define SYM(name) name
#endif

/* ---- strlen ---- */
.globl SYM(rt_strlen_neon)
#ifndef __APPLE__
.type SYM(rt_strlen_neon), %function
#endif
.p2align 5
SYM(rt_strlen_neon):
    mov     x9, x0
    and     x2, x0, #0xfff
    cmp     x2, #0xff0
    b.hi    10f

20:
    ldp     q0, q1, [x0]
    cmeq    v2.16b, v0.16b, #0
    cmeq    v3.16b, v1.16b, #0
    orr     v4.16b, v2.16b, v3.16b
    umaxv   b5, v4.16b
    umov    w3, v5.b[0]
    cbnz    w3, 30f
    add     x0, x0, #32
    and     x2, x0, #0xfff
    cmp     x2, #0xff0
    b.ls    20b
    b       10f

30:
    umaxv   b5, v2.16b
    umov    w3, v5.b[0]
    cbnz    w3, 40f
    add     x0, x0, #16
    mov     v2.16b, v3.16b
40:
    shrn    v2.8b, v2.8h, #4
    fmov    x2, d2
    rbit    x2, x2
    clz     x2, x2
    add     x0, x0, x2, lsr #2
    sub     x0, x0, x9
    ret

10:
    ldrb    w3, [x0]
    cbz     w3, 11f
    add     x0, x0, #1
    and     x2, x0, #0xfff
    cbnz    x2, 10b
    b       20b
11:
    sub     x0, x0, x9
    ret

/* ---- strcmp ---- */
.globl SYM(rt_strcmp_neon)
#ifndef __APPLE__
.type SYM(rt_strcmp_neon), %function
#endif
.p2align 5
SYM(rt_strcmp_neon):
50:
    ldp     q0, q1, [x0]
    ldp     q2, q3, [x1]
    cmeq    v4.16b, v0.16b, v2.16b
    cmeq    v5.16b, v1.16b, v3.16b
    uminv   b6, v4.16b
    umov    w2, v6.b[0]
    cmp     w2, #0xff
    b.ne    60f
    uminv   b6, v5.16b
    umov    w2, v6.b[0]
    cmp     w2, #0xff
    b.ne    55f
    cmeq    v4.16b, v0.16b, #0
    cmeq    v5.16b, v1.16b, #0
    orr     v6.16b, v4.16b, v5.16b
    umaxv   b7, v6.16b
    umov    w2, v7.b[0]
    cbnz    w2, 70f
    add     x0, x0, #32
    add     x1, x1, #32
    b       50b

55:
    add     x0, x0, #16
    add     x1, x1, #16
    mov     v0.16b, v1.16b
    mov     v2.16b, v3.16b
60:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    subs    w2, w2, w3
    b.ne    71f
    cbnz    w3, 60b
70:
    mov     w0, #0
    ret
71:
    mov     w0, w2
    ret

/* ---- strchr ---- */
.globl SYM(rt_strchr_neon)
#ifndef __APPLE__
.type SYM(rt_strchr_neon), %function
#endif
.p2align 5
SYM(rt_strchr_neon):
    and     w1, w1, #0xff
    dup     v1.16b, w1
    and     x2, x0, #0xfff
    cmp     x2, #0xff0
    b.hi    90f

80:
    ldp     q0, q2, [x0]
    cmeq    v3.16b, v0.16b, v1.16b
    cmeq    v4.16b, v2.16b, v1.16b
    cmeq    v5.16b, v0.16b, #0
    cmeq    v6.16b, v2.16b, #0
    orr     v3.16b, v3.16b, v5.16b
    orr     v4.16b, v4.16b, v6.16b
    orr     v7.16b, v3.16b, v4.16b
    umaxv   b16, v7.16b
    umov    w3, v16.b[0]
    cbnz    w3, 85f
    add     x0, x0, #32
    and     x2, x0, #0xfff
    cmp     x2, #0xff0
    b.ls    80b
    b       90f

85:
    umaxv   b16, v3.16b
    umov    w3, v16.b[0]
    cbnz    w3, 86f
    add     x0, x0, #16
    mov     v3.16b, v4.16b
    mov     v0.16b, v2.16b
86:
    shrn    v3.8b, v3.8h, #4
    fmov    x2, d3
    rbit    x2, x2
    clz     x2, x2
    lsr     x2, x2, #2
    ldrb    w3, [x0, x2]
    cmp     w3, w1
    b.ne    91f
    add     x0, x0, x2
    ret

90:
    ldrb    w3, [x0]
    cmp     w3, w1
    b.eq    92f
    cbz     w3, 91f
    add     x0, x0, #1
    and     x2, x0, #0xfff
    cbnz    x2, 90b
    b       80b
91:
    mov     x0, #0
    ret
92:
    ret
