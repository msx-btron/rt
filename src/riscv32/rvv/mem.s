# RV32GCV. Same vsetvli e8 m8 loop as RV64: VLEN does not follow XLEN,
# so one vle8/vse8 still moves VL bytes and stops on n.
# a0-a7 and t0 are XLEN wide (32 here). Do not assemble this into an
# RV64 link; the symbol names match the RV64 file on purpose.

.section .text
.attribute arch, "rv32gcv"

.globl rt_memcpy_rvv
.type rt_memcpy_rvv, @function
.p2align 2
rt_memcpy_rvv:
    mv t1, a0
1:
    vsetvli t0, a2, e8, m8, ta, ma
    vle8.v v0, (a1)
    vse8.v v0, (a0)
    add a0, a0, t0
    add a1, a1, t0
    sub a2, a2, t0
    bnez a2, 1b
    mv a0, t1
    ret

.globl rt_memset_rvv
.type rt_memset_rvv, @function
.p2align 2
rt_memset_rvv:
    mv t1, a0
    andi a1, a1, 255
1:
    vsetvli t0, a2, e8, m8, ta, ma
    vmv.v.x v0, a1
    vse8.v v0, (a0)
    add a0, a0, t0
    sub a2, a2, t0
    bnez a2, 1b
    mv a0, t1
    ret

.globl rt_memcmp_rvv
.type rt_memcmp_rvv, @function
.p2align 2
rt_memcmp_rvv:
    beqz a2, 3f
1:
    vsetvli t0, a2, e8, m8, ta, ma
    vle8.v v8, (a0)
    vle8.v v16, (a1)
    vmsne.vv v0, v8, v16
    vfirst.m t1, v0
    bgez t1, 2f
    add a0, a0, t0
    add a1, a1, t0
    sub a2, a2, t0
    bnez a2, 1b
3:
    li a0, 0
    ret
2:
    add a0, a0, t1
    add a1, a1, t1
    lbu t2, (a0)
    lbu t3, (a1)
    sub a0, t2, t3
    ret
