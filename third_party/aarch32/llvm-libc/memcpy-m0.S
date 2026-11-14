/* clang -S of LLVM libc inline_memcpy.h at a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0.
   Cortex-M0, inline_memcpy_arm_low_end (no __ARM_FEATURE_UNALIGNED).
   Apache-2.0 WITH LLVM-exception. Compiler output of the upstream header.
   Not an RT kernel.
   Command:
     clang -std=c++17 -O2 -S -fno-exceptions -fno-rtti -nostdinc++ -ffreestanding
       -fno-builtin -DLIBC_NAMESPACE=__llvm_libc
       --target=thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb 
       third_party/aarch32/llvm-libc/driver.cpp
   The thumb none-eabi target has no C library, so stddef.h and stdint.h were
   freestanding stubs. The header tree was the pinned llvm-project commit.
*/
	.syntax	unified
	.eabi_attribute	67, "2.09"	@ Tag_conformance
	.cpu	cortex-m0
	.eabi_attribute	6, 12	@ Tag_CPU_arch
	.eabi_attribute	7, 77	@ Tag_CPU_arch_profile
	.eabi_attribute	8, 0	@ Tag_ARM_ISA_use
	.eabi_attribute	9, 1	@ Tag_THUMB_ISA_use
	.eabi_attribute	34, 0	@ Tag_CPU_unaligned_access
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
	.p2align	1
	.type	memcpy,%function
	.code	16
	.thumb_func
memcpy:                                 @ @memcpy
	.fnstart
@ %bb.0:
	.save	{r4, lr}
	push	{r4, lr}
	mov	r4, r0
	bl	_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j
	mov	r0, r4
	pop	{r4, pc}
.Lfunc_end0:
	.size	memcpy, .Lfunc_end0-memcpy
	.cantunwind
	.fnend
                                        @ -- End function
	.section	.text._ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j,"axG",%progbits,_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j,comdat
	.hidden	_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j @ -- Begin function _ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j
	.weak	_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j
	.p2align	1
	.type	_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j,%function
	.code	16
	.thumb_func
_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j: @ @_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j
	.fnstart
@ %bb.0:
	.save	{r4, r5, r6, r7, lr}
	push	{r4, r5, r6, r7, lr}
	.pad	#12
	sub	sp, #12
	mov	r7, r2
	@APP
	@NO_APP
	cmp	r2, #8
	blo	.LBB1_10
@ %bb.1:
	rsbs	r4, r0, #0
	movs	r2, #3
	ands	r4, r2
	bne	.LBB1_13
.LBB1_2:
	mov	r4, r1
	ands	r4, r2
	bne	.LBB1_16
@ %bb.3:
	str	r2, [sp]                        @ 4-byte Spill
	str	r7, [sp, #4]                    @ 4-byte Spill
	lsrs	r2, r7, #6
	beq	.LBB1_5
.LBB1_4:                                @ =>This Inner Loop Header: Depth=1
	str	r2, [sp, #8]                    @ 4-byte Spill
	mov	r5, r1
	mov	r6, r0
	ldm	r5!, {r2, r3, r4, r7}
	stm	r6!, {r2, r3, r4, r7}
	ldm	r5!, {r2, r3, r4, r7}
	stm	r6!, {r2, r3, r4, r7}
	ldm	r5!, {r2, r3, r4, r7}
	stm	r6!, {r2, r3, r4, r7}
	ldm	r5!, {r2, r3, r4, r7}
	stm	r6!, {r2, r3, r4, r7}
	ldr	r2, [sp, #8]                    @ 4-byte Reload
	adds	r1, #64
	adds	r0, #64
	subs	r2, r2, #1
	bne	.LBB1_4
.LBB1_5:
	ldr	r7, [sp, #4]                    @ 4-byte Reload
	lsls	r2, r7, #26
	lsrs	r4, r2, #30
	beq	.LBB1_7
.LBB1_6:                                @ =>This Inner Loop Header: Depth=1
	ldr	r2, [r1]
	str	r2, [r0]
	ldr	r2, [r1, #4]
	str	r2, [r0, #4]
	ldr	r2, [r1, #8]
	str	r2, [r0, #8]
	ldr	r2, [r1, #12]
	str	r2, [r0, #12]
	adds	r1, #16
	adds	r0, #16
	subs	r4, r4, #1
	bne	.LBB1_6
.LBB1_7:
	lsls	r2, r7, #28
	lsrs	r4, r2, #30
	beq	.LBB1_9
.LBB1_8:                                @ =>This Inner Loop Header: Depth=1
	ldm	r1!, {r2}
	stm	r0!, {r2}
	subs	r4, r4, #1
	bne	.LBB1_8
.LBB1_9:
	ldr	r2, [sp]                        @ 4-byte Reload
	ands	r7, r2
.LBB1_10:
	cmp	r7, #0
	beq	.LBB1_12
.LBB1_11:                               @ =>This Inner Loop Header: Depth=1
	ldrb	r2, [r1]
	strb	r2, [r0]
	adds	r0, r0, #1
	adds	r1, r1, #1
	subs	r7, r7, #1
	bne	.LBB1_11
.LBB1_12:
	add	sp, #12
	pop	{r4, r5, r6, r7, pc}
.LBB1_13:
	mov	r5, r4
.LBB1_14:                               @ =>This Inner Loop Header: Depth=1
	ldrb	r6, [r1]
	strb	r6, [r0]
	adds	r0, r0, #1
	adds	r1, r1, #1
	subs	r5, r5, #1
	bne	.LBB1_14
@ %bb.15:
	subs	r7, r7, r4
	b	.LBB1_2
.LBB1_16:
	movs	r3, #0
	b	.LBB1_19
.LBB1_17:                               @   in Loop: Header=BB1_19 Depth=1
	ldrb	r2, [r1, r3]
	adds	r5, r1, r3
	movs	r6, #1
	ldrh	r6, [r5, r6]
	lsls	r6, r6, #8
	adds	r2, r6, r2
	ldrb	r5, [r5, #3]
	lsls	r5, r5, #24
	adds	r5, r2, r5
.LBB1_18:                               @   in Loop: Header=BB1_19 Depth=1
	str	r5, [r0, r3]
	adds	r3, r3, #4
	subs	r7, r7, #4
	cmp	r7, #3
	bls	.LBB1_21
.LBB1_19:                               @ =>This Inner Loop Header: Depth=1
	cmp	r4, #2
	bne	.LBB1_17
@ %bb.20:                               @   in Loop: Header=BB1_19 Depth=1
	ldrh	r2, [r1, r3]
	adds	r5, r1, r3
	ldrh	r5, [r5, #2]
	lsls	r5, r5, #16
	adds	r5, r5, r2
	b	.LBB1_18
.LBB1_21:
	adds	r1, r1, r3
	adds	r0, r0, r3
	cmp	r7, #0
	bne	.LBB1_11
	b	.LBB1_12
.Lfunc_end1:
	.size	_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j, .Lfunc_end1-_ZN11__llvm_libc17inline_memcpy_armEPNS_3cpp4byteEPKS1_j
	.cantunwind
	.fnend
                                        @ -- End function
	.ident	"Homebrew clang version 22.1.8"
	.section	".note.GNU-stack","",%progbits
	.addrsig
	.eabi_attribute	30, 1	@ Tag_ABI_optimization_goals
