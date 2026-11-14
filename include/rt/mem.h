#ifndef RT_MEM_H
#define RT_MEM_H

#include <stddef.h>

/* Non-overlapping, like ISO C memcpy. Overlap is undefined.
   memset converts c to unsigned char. memcmp compares unsigned bytes.
   Every routine returns dst (memcpy/memset) or the usual <0/0/>0 (memcmp).

   Tiers (pick one at compile time, or probe once):
     scalar     portable C99, word-at-a-time
     i386       80386 REP MOVSD/STOSD (best general RAM copy on 386/486)
     pc98       same RAM path, plus 16-bit VRAM path (MOVSW/STOSW)
     pc98 real  .code16 helpers, BIOS register convention, not the ELF ABI
     mmx        Pentium MMX movq, EMMS on every exit that touched MMX
     sse        i386 XMM movups/movaps (Pentium III; no SSE2 integer ops)
     sse2       x86-64, 16-byte, dest-aligned movdqa
     avx        x86-64, 32-byte, AVX1, vzeroupper on every return
     avx2       x86-64, 32-byte, vzeroupper on every return
     avx512     x86-64, 64-byte ZMM, AVX-512F+BW; leaves ZMM state dirty
     neon/sve   AArch64
     sme        Apple SME2. memcpy, memmove, memset, memcmp.
                The proved neon memset stays separate.
     rvv        RV32 or RV64 V, m8 e8 (one object per XLEN).
                memcpy, memset, memcmp. memmove stays scalar.
*/

void *rt_memcpy_scalar(void *dst, const void *src, size_t n);
void *rt_memmove_scalar(void *dst, const void *src, size_t n);
void *rt_memset_scalar(void *dst, int c, size_t n);
int   rt_memcmp_scalar(const void *a, const void *b, size_t n);

void *rt_memcpy_i386(void *dst, const void *src, size_t n);
void *rt_memset_i386(void *dst, int c, size_t n);
int   rt_memcmp_i386(const void *a, const void *b, size_t n);

void *rt_memcpy_pc98(void *dst, const void *src, size_t n);
void *rt_memset_pc98(void *dst, int c, size_t n);
int   rt_memcmp_pc98(const void *a, const void *b, size_t n);
void *rt_memcpy_pc98_vram(void *dst, const void *src, size_t n);
void *rt_memset_pc98_vram(void *dst, int c, size_t n);

void *rt_memcpy_mmx(void *dst, const void *src, size_t n);
void *rt_memset_mmx(void *dst, int c, size_t n);
int   rt_memcmp_mmx(const void *a, const void *b, size_t n);

void *rt_memcpy_sse(void *dst, const void *src, size_t n);
void *rt_memset_sse(void *dst, int c, size_t n);
int   rt_memcmp_sse(const void *a, const void *b, size_t n);

void *rt_memcpy_sse2(void *dst, const void *src, size_t n);
void *rt_memset_sse2(void *dst, int c, size_t n);
int   rt_memcmp_sse2(const void *a, const void *b, size_t n);

void *rt_memcpy_avx(void *dst, const void *src, size_t n);
void *rt_memset_avx(void *dst, int c, size_t n);
int   rt_memcmp_avx(const void *a, const void *b, size_t n);

void *rt_memcpy_avx2(void *dst, const void *src, size_t n);
void *rt_memset_avx2(void *dst, int c, size_t n);
int   rt_memcmp_avx2(const void *a, const void *b, size_t n);

void *rt_memcpy_avx512(void *dst, const void *src, size_t n);
void *rt_memset_avx512(void *dst, int c, size_t n);
int   rt_memcmp_avx512(const void *a, const void *b, size_t n);

void *rt_memcpy_neon(void *dst, const void *src, size_t n);
void *rt_memset_neon(void *dst, int c, size_t n);
int   rt_memcmp_neon(const void *a, const void *b, size_t n);

void *rt_memcpy_sve(void *dst, const void *src, size_t n);
void *rt_memset_sve(void *dst, int c, size_t n);
int   rt_memcmp_sve(const void *a, const void *b, size_t n);

void *rt_memcpy_sme(void *dst, const void *src, size_t n);
void *rt_memmove_sme(void *dst, const void *src, size_t n);
void *rt_memset_sme(void *dst, int c, size_t n);
int   rt_memcmp_sme(const void *a, const void *b, size_t n);

void *rt_memcpy_rvv(void *dst, const void *src, size_t n);
void *rt_memset_rvv(void *dst, int c, size_t n);
int   rt_memcmp_rvv(const void *a, const void *b, size_t n);

#endif
