/* ARMv8-M Mainline integer. STM32H5, L5, U5, U3, WBA, C5.
   Optional DSP is not required. The body runs on every M33.
   The libc text is the Thumb-2 M3 body. NuttX armv8-m is the same
   Mike Smith memcpy and is not imported again. No PAC string path.
   memcpy: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/memcpy-armv7m.S
   memcpy: https://github.com/NuttX/nuttx/blob/6b31918b429e6b2351bfa03f005704d123cb70e9/libs/libc/machine/arm/armv7-m/gnu/arch_memcpy.S
   memcpy: https://github.com/llvm/llvm-project/blob/a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0/libc/src/string/memory_utils/arm/inline_memcpy.h
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m33
.thumb
#define RT_SUF m33
#define RT_UNALIGNED 1
#define RT_PLD 0
#define RT_WIDE 0
#include "../thumb2/mem.inc"
