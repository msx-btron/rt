/* clang -S of LLVM libc inline_memcpy.h at a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0.
   Cortex-M7. Same mid-end, with the ldr [r1, #64]! prefetch scheduled for this cpu.
   Apache-2.0 WITH LLVM-exception. Compiler output of the upstream header.
   Not an RT kernel.
   Command:
     clang -std=c++17 -O2 -S -fno-exceptions -fno-rtti -nostdinc++ -ffreestanding
       -fno-builtin -DLIBC_NAMESPACE=__llvm_libc
       --target=thumbv7em-none-eabi -mcpu=cortex-m7 -mthumb -mfpu=none
       third_party/aarch32/llvm-libc/driver.cpp
   The thumb none-eabi target has no C library, so stddef.h and stdint.h were
   freestanding stubs. The header tree was the pinned llvm-project commit.
*/
	.syntax	unified
	.eabi_attribute	67, "2.09"	@ Tag_conformance
	.cpu	cortex-m7
	.eabi_attribute	6, 13	@ Tag_CPU_arch
	.eabi_attribute	7, 77	@ Tag_CPU_arch_profile
	.eabi_attribute	8, 0	@ Tag_ARM_ISA_use
	.eabi_attribute	9, 2	@ Tag_THUMB_ISA_use
	.eabi_attribute	34, 1	@ Tag_CPU_unaligned_access
	.eabi_attribute	17, 1	@ Tag_ABI_PCS_GOT_use
	.eabi_attribute	20, 1	@ Tag_ABI_FP_denormal
	.eabi_attribute	21, 0	@ Tag_ABI_FP_exceptions
	.eabi_attribute	23, 3	@ Tag_ABI_FP_number_model
	.eabi_attribute	24, 1	@ Tag_ABI_align_needed
	.eabi_attribute	25, 1	@ Tag_ABI_align_preserved
	.eabi_attribute	38, 1	@ Tag_ABI_FP_16bit_format
	.eabi_attribute	18, 4	@ Tag_ABI_PCS_wchar_t
	.eabi_attribute	26, 2	@ Tag_ABI_enum_size
	.eabi_attribute	14, 0	@ Tag_ABI_PCS_R9_use
	.file	"driver.cpp"
	.text
	.globl	memcpy                          @ -- Begin function memcpy
	.p2align	3
	.type	memcpy,%function
	.code	16
	.thumb_func
memcpy:                                 @ @memcpy
	.fnstart
@ %bb.0:
	.save	{r4, lr}
	push	{r4, lr}
	mov	r4, r0
	@APP
	@NO_APP
	bl	_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j
	mov	r0, r4
	pop	{r4, pc}
.Lfunc_end0:
	.size	memcpy, .Lfunc_end0-memcpy
	.cantunwind
	.fnend
                                        @ -- End function
	.section	.text._ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j,"axG",%progbits,_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j,comdat
	.hidden	_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j @ -- Begin function _ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j
	.weak	_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j
	.p2align	3
	.type	_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j,%function
	.code	16
	.thumb_func
_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j: @ @_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j
	.fnstart
@ %bb.0:
	orr.w	r3, r1, r0
	lsls	r3, r3, #30
	bne	.LBB1_18
.LBB1_1:
	lsrs.w	r12, r2, #6
	beq	.LBB1_5
@ %bb.2:
	subs	r1, #64
	.p2align	3
.LBB1_3:                                @ =>This Inner Loop Header: Depth=1
	ldr	r3, [r1, #64]!
	str	r3, [r0]
	ldr	r3, [r1, #4]
	str	r3, [r0, #4]
	ldr	r3, [r1, #8]
	str	r3, [r0, #8]
	ldr	r3, [r1, #12]
	str	r3, [r0, #12]
	ldr	r3, [r1, #16]
	str	r3, [r0, #16]
	ldr	r3, [r1, #20]
	str	r3, [r0, #20]
	ldr	r3, [r1, #24]
	str	r3, [r0, #24]
	ldr	r3, [r1, #28]
	str	r3, [r0, #28]
	ldr	r3, [r1, #32]
	str	r3, [r0, #32]
	ldr	r3, [r1, #36]
	str	r3, [r0, #36]
	ldr	r3, [r1, #40]
	str	r3, [r0, #40]
	ldr	r3, [r1, #44]
	str	r3, [r0, #44]
	ldr	r3, [r1, #48]
	str	r3, [r0, #48]
	ldr	r3, [r1, #52]
	str	r3, [r0, #52]
	ldr	r3, [r1, #56]
	str	r3, [r0, #56]
	ldr	r3, [r1, #60]
	subs.w	r12, r12, #1
	str	r3, [r0, #60]
	add.w	r0, r0, #64
	bne	.LBB1_3
@ %bb.4:
	adds	r1, #64
.LBB1_5:
	ubfx	r12, r2, #4, #2
	cmp.w	r12, #0
	beq	.LBB1_9
@ %bb.6:
	subs	r1, #16
	.p2align	3
.LBB1_7:                                @ =>This Inner Loop Header: Depth=1
	ldr	r3, [r1, #16]!
	str	r3, [r0]
	ldr	r3, [r1, #4]
	str	r3, [r0, #4]
	ldr	r3, [r1, #8]
	str	r3, [r0, #8]
	ldr	r3, [r1, #12]
	subs.w	r12, r12, #1
	str	r3, [r0, #12]
	add.w	r0, r0, #16
	bne	.LBB1_7
@ %bb.8:
	adds	r1, #16
.LBB1_9:
	ubfx	r12, r2, #2, #2
	cmp.w	r12, #0
	beq	.LBB1_13
@ %bb.10:
	subs	r1, #4
	.p2align	3
.LBB1_11:                               @ =>This Inner Loop Header: Depth=1
	subs.w	r12, r12, #1
	ldr	r3, [r1, #4]!
	str	r3, [r0], #4
	bne	.LBB1_11
@ %bb.12:
	adds	r1, #4
.LBB1_13:
	lsls	r3, r2, #31
	beq	.LBB1_15
@ %bb.14:
	ldrb	r3, [r1], #1
	strb	r3, [r0], #1
.LBB1_15:
	lsls	r2, r2, #30
	it	pl
	bxpl	lr
.LBB1_16:
	ldrh	r1, [r1]
	strh	r1, [r0]
.LBB1_17:
	bx	lr
.LBB1_18:
	cmp	r2, #7
	bls	.LBB1_25
@ %bb.19:
	lsls	r3, r1, #30
	beq	.LBB1_1
@ %bb.20:
	rsb.w	r12, r0, #0
	lsls.w	r3, r12, #31
	beq	.LBB1_22
@ %bb.21:
	ldrb	r3, [r1], #1
	strb	r3, [r0], #1
.LBB1_22:
	lsls.w	r3, r12, #30
	and	r12, r12, #3
	bpl	.LBB1_24
@ %bb.23:
	ldrh	r3, [r1], #2
	strh	r3, [r0], #2
.LBB1_24:
	sub.w	r2, r2, r12
	b	.LBB1_1
.LBB1_25:
	lsls	r3, r2, #31
	bne	.LBB1_28
@ %bb.26:
	lsls	r3, r2, #30
	bmi	.LBB1_29
.LBB1_27:
	cmp	r2, #4
	blo	.LBB1_17
	b	.LBB1_30
.LBB1_28:
	ldrb	r3, [r1], #1
	strb	r3, [r0], #1
	lsls	r3, r2, #30
	bpl	.LBB1_27
.LBB1_29:
	ldrh	r3, [r1], #2
	strh	r3, [r0], #2
	cmp	r2, #4
	blo	.LBB1_17
.LBB1_30:
	ldr	r1, [r1]
	str	r1, [r0]
	bx	lr
.Lfunc_end1:
	.size	_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j, .Lfunc_end1-_ZN11__llvm_libc25inline_memcpy_arm_mid_endEPNS_3cpp4byteEPKS1_j
	.cantunwind
	.fnend
                                        @ -- End function
	.ident	"Homebrew clang version 22.1.8"
	.section	".note.GNU-stack","",%progbits
	.addrsig
	.eabi_attribute	30, 1	@ Tag_ABI_optimization_goals
