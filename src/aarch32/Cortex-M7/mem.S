/* ARMv7E-M with PLD. STM32F7 and the M7 core of STM32H7.
   Thirty-two byte LDM plus a prefetch. The M4 object has neither.
   picolibc has no separate M7 file. The LLVM mid-end schedules
   ldr r3, [r1, #64]! as its prefetch.
   memcpy: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/memcpy-armv7m.S
   memcpy: https://github.com/NuttX/nuttx/blob/6b31918b429e6b2351bfa03f005704d123cb70e9/libs/libc/machine/arm/armv7-m/gnu/arch_memcpy.S
   memcpy: https://github.com/llvm/llvm-project/blob/a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0/libc/src/string/memory_utils/arm/inline_memcpy.h
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m7
.thumb
#define RT_SUF m7
#define RT_UNALIGNED 1
#define RT_PLD 1
#define RT_WIDE 1
#include "../thumb2/mem.inc"
