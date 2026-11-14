/* ARMv7E-M integer. STM32F3, F4, G4, L4, L4+, WB (M4 core), WL,
   and the M4 core of STM32H7. DSP packed arithmetic is not an ordered
   memcmp, so this object uses the same word moves as Cortex-M3.
   The libc bodies are the M3 ones. No imported libc uses the DSP unit.
   memcpy: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/memcpy-armv7m.S
   memcpy: https://github.com/NuttX/nuttx/blob/6b31918b429e6b2351bfa03f005704d123cb70e9/libs/libc/machine/arm/armv7-m/gnu/arch_memcpy.S
   memcpy: https://github.com/llvm/llvm-project/blob/a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0/libc/src/string/memory_utils/arm/inline_memcpy.h
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m4
.thumb
#define RT_SUF m4
#define RT_UNALIGNED 1
#define RT_PLD 0
#define RT_WIDE 0
#include "../thumb2/mem.inc"
