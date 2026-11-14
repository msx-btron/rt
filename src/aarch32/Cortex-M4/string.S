/* ARMv7E-M strings. Same Thumb-2 integer routines as Cortex-M3.
   strlen: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/strlen-thumb2-Os.S
   strcmp: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/strcmp-armv7m.S
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m4
.thumb
#define RT_SUF m4
#include "../thumb2/string.inc"
