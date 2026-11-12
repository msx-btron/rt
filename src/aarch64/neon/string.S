/* AArch64 NEON strlen / strcmp / strchr */

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
.p2align 4
SYM(rt_strlen_neon):
    mov x9, x0
    ands x2, x0, #15
    b.eq .Ls_al
    mov x3, #16
    sub x2, x3, x2
.Ls_hd:
    ldrb w3, [x0], #1
    cbz w3, .Ls_done
    subs x2, x2, #1
    b.ne .Ls_hd
.Ls_al:
.p2align 4
.Ls_lp:
    ldr q0, [x0]
    cmeq v1.16b, v0.16b, #0
    uminv b2, v1.16b
    umov w3, v2.b[0]
    cbnz w3, .Ls_blk
    add x0, x0, #16
    b .Ls_lp
.Ls_blk:
    mov x2, #0
1:
    ldrb w3, [x0, x2]
    cbz w3, 2f
    add x2, x2, #1
    cmp x2, #16
    b.lo 1b
2:
    add x0, x0, x2
.Ls_done:
    sub x0, x0, x9
    ret

/* ---- strcmp ---- */
.globl SYM(rt_strcmp_neon)
#ifndef __APPLE__
.type SYM(rt_strcmp_neon), %function
#endif
.p2align 4
SYM(rt_strcmp_neon):
.Lsc_lp:
    ldr q0, [x0]
    ldr q1, [x1]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b3, v2.16b
    umov w2, v3.b[0]
    cmp w2, #0xff
    b.ne .Lsc_byte
    cmeq v2.16b, v0.16b, #0
    uminv b3, v2.16b
    umov w2, v3.b[0]
    cbnz w2, .Lsc_eq
    add x0, x0, #16
    add x1, x1, #16
    b .Lsc_lp
.Lsc_byte:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    subs w2, w2, w3
    b.ne .Lsc_ret
    cbnz w3, .Lsc_byte
.Lsc_eq:
    mov w0, #0
    ret
.Lsc_ret:
    mov w0, w2
    ret

/* ---- strchr ---- */
.globl SYM(rt_strchr_neon)
#ifndef __APPLE__
.type SYM(rt_strchr_neon), %function
#endif
.p2align 4
SYM(rt_strchr_neon):
    and w1, w1, #0xff
    dup v1.16b, w1
    ands x2, x0, #15
    b.eq .Lch_al
    mov x3, #16
    sub x2, x3, x2
.Lch_hd:
    ldrb w3, [x0], #1
    cmp w3, w1
    b.eq .Lch_hit
    cbz w3, .Lch_none
    subs x2, x2, #1
    b.ne .Lch_hd
.Lch_al:
.p2align 4
.Lch_lp:
    ldr q0, [x0]
    cmeq v2.16b, v0.16b, v1.16b
    cmeq v3.16b, v0.16b, #0
    orr v4.16b, v2.16b, v3.16b
    uminv b5, v4.16b
    umov w3, v5.b[0]
    cbnz w3, .Lch_blk
    add x0, x0, #16
    b .Lch_lp
.Lch_blk:
    mov x2, #0
1:
    ldrb w3, [x0, x2]
    cmp w3, w1
    b.eq 2f
    cbz w3, .Lch_none
    add x2, x2, #1
    cmp x2, #16
    b.lo 1b
    add x0, x0, #16
    b .Lch_lp
2:
    add x0, x0, x2
    ret
.Lch_hit:
    sub x0, x0, #1
    ret
.Lch_none:
    mov x0, #0
    ret
